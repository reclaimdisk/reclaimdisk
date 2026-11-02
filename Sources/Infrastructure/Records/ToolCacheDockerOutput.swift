import Catalog
import Foundation
import SharedKernel

/// Pure parsers for Docker's JSON lines. A line that is not a JSON object, or a missing field, fails the whole result.
enum DockerOutput {
    /// Decimal units (1 kB = 1000 bytes). A trailing `" (NN%)"` is Docker's reclaimable share and is ignored.
    static func size(_ text: String) -> ByteCount? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = trimmed.range(of: " (", options: .backwards) {
            let suffix = trimmed[marker.upperBound...]
            let percent = suffix.dropLast(2)
            if suffix.hasSuffix("%)"), !percent.isEmpty, percent.allSatisfy({ $0.isNumber || $0 == "." }) {
                trimmed = String(trimmed[..<marker.lowerBound])
            }
        }
        let units: [(String, UInt64)] = [
            ("TB", 1_000_000_000_000), ("GB", 1_000_000_000), ("MB", 1_000_000), ("KB", 1_000), ("kB", 1_000), ("B", 1),
        ]
        for (unit, scale) in units where trimmed.hasSuffix(unit) {
            let number = trimmed.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
            guard let bytes = scaled(String(number), by: scale) else { return nil }
            return ByteCount(bytes)
        }
        return nil
    }

    static func systemDF(_ text: String) -> (buildCacheReclaimable: ByteCount, volumesReclaimable: ByteCount)? {
        var buildCache: ByteCount?
        var volumes: ByteCount?
        for line in contentLines(text) {
            guard let object = JSONLine.parse(line), let type = object.field("Type"), let reclaimable = object.field("Reclaimable"),
                  let parsed = size(reclaimable) else { return nil }
            if type == "Build Cache" { buildCache = parsed }
            if type == "Local Volumes" { volumes = parsed }
        }
        guard let buildCache, let volumes else { return nil }
        return (buildCache, volumes)
    }

    static func images(_ text: String, containers: String) -> [DockerImage]? {
        guard let containerImages = field("Image", in: containers) else { return nil }
        var images: [DockerImage] = []
        for line in contentLines(text) {
            guard let object = JSONLine.parse(line), let id = object.field("ID"), let repository = object.field("Repository"),
                  let tag = object.field("Tag"), let created = object.field("CreatedAt"), let sizeText = object.field("Size"),
                  let createdAt = instant(fromDockerCreatedAt: created), let imageSize = size(sizeText) else { return nil }
            // An untagged image has no repository:tag, so a container names it by id.
            let reference = repository == "<none>" ? id : "\(repository):\(tag)"
            let used = containerImages.contains { containerUses(imageID: id, reference: reference, containerImage: $0) }
            images.append(DockerImage(id: id, reference: reference, createdAt: createdAt, size: imageSize, usedByContainer: used))
        }
        return images
    }

    static func volumes(_ text: String, containers: String) -> [DockerVolume]? {
        guard let mounts = mountedNames(in: containers) else { return nil }
        var volumes: [DockerVolume] = []
        for line in contentLines(text) {
            guard let object = JSONLine.parse(line), let name = object.field("Name"), let labels = object.field("Labels") else {
                return nil
            }
            volumes.append(DockerVolume(
                name: name, isAnonymous: labels.contains("com.docker.volume.anonymous"), usedByContainer: mounts.contains(name)
            ))
        }
        return volumes
    }
}

/// `yyyy-MM-dd HH:mm:ss Z zzz`, for example `2026-11-02 00:31:30 +0100 CET`. The numeric offset decides the instant.
private func instant(fromDockerCreatedAt text: String) -> Instant? {
    let parts = text.split(separator: " ")
    guard parts.count >= 4 else { return nil }
    let date = parts[0].split(separator: "-")
    let time = parts[1].split(separator: ":")
    guard date.count == 3, time.count == 3 else { return nil }
    guard let year = Int(date[0]), let month = Int(date[1]), let day = Int(date[2]) else { return nil }
    guard let hour = Int(time[0]), let minute = Int(time[1]), let second = Int(time[2]) else { return nil }
    let zone = parts[2]
    guard !parts[3].isEmpty, zone.count == 5, zone.first == "+" || zone.first == "-" else { return nil }
    let digits = zone.dropFirst()
    guard let zoneHour = Int(digits.prefix(2)), let zoneMinute = Int(digits.suffix(2)) else { return nil }
    guard (1...9999).contains(year), (1...12).contains(month), (1...daysInMonth(year: year, month: month)).contains(day) else {
        return nil
    }
    guard (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second) else { return nil }
    guard (0...23).contains(zoneHour), (0...59).contains(zoneMinute) else { return nil }
    guard let days = daysSinceUnixEpoch(year: year, month: month, day: day) else { return nil }
    let sign: Int64 = zone.first == "+" ? 1 : -1
    let offset = sign * (Int64(zoneHour) * 3600 + Int64(zoneMinute) * 60)
    let local = days * 86_400 + Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
    return Instant(nanosecondsSince1970: (local - offset) * 1_000_000_000)
}

private func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12: 31
    case 4, 6, 9, 11: 30
    case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    default: 0
    }
}

/// Howard Hinnant's civil-from-days, inverted: days since 1970-01-01.
private func daysSinceUnixEpoch(year: Int, month: Int, day: Int) -> Int64? {
    var year = year
    year -= month <= 2 ? 1 : 0
    let era = (year >= 0 ? year : year - 399) / 400
    let yearOfEra = year - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return Int64(era * 146097 + dayOfEra - 719468)
}

private func scaled(_ number: String, by scale: UInt64) -> UInt64? {
    let pieces = number.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count == 1 || pieces.count == 2, let whole = UInt64(pieces[0]), !pieces[0].isEmpty else { return nil }
    let (wholeScaled, wholeOverflowed) = whole.multipliedReportingOverflow(by: scale)
    guard !wholeOverflowed else { return nil }
    guard pieces.count == 2 else { return wholeScaled }
    let fraction = pieces[1]
    guard !fraction.isEmpty, fraction.allSatisfy(\.isNumber), let fractionNumber = UInt64(fraction) else { return nil }
    var divisor: UInt64 = 1
    for _ in fraction {
        let (next, overflowed) = divisor.multipliedReportingOverflow(by: 10)
        guard !overflowed else { return nil }
        divisor = next
    }
    let (product, productOverflowed) = fractionNumber.multipliedReportingOverflow(by: scale)
    guard !productOverflowed else { return nil }
    let (sum, sumOverflowed) = wholeScaled.addingReportingOverflow(product / divisor)
    guard !sumOverflowed else { return nil }
    return sum
}

/// A container may name an image as `repository:tag`, `repository:tag@sha256:<digest>`, or `sha256:<digest>`.
/// `docker image ls` prints a short id; the container may carry the full digest.
private func containerUses(imageID: String, reference: String, containerImage: String) -> Bool {
    if containerImage == reference || containerImage == imageID { return true }
    let pieces = containerImage.split(separator: "@", maxSplits: 1)
    if pieces.count == 2, String(pieces[0]) == reference { return true }
    let loweredID = imageID.lowercased()
    guard !loweredID.isEmpty else { return false }
    let lowered = containerImage.lowercased()
    let digest: String
    if let range = lowered.range(of: "sha256:") {
        digest = String(lowered[range.upperBound...])
    } else {
        digest = lowered
    }
    guard !digest.isEmpty, digest.allSatisfy(\.isHexDigit) else { return false }
    if digest == loweredID || digest.hasPrefix(loweredID) { return true }
    return loweredID.hasPrefix(digest) && digest.count >= 12
}

private func mountedNames(in containers: String) -> Set<String>? {
    guard let mountFields = field("Mounts", in: containers) else { return nil }
    var names: Set<String> = []
    for mounts in mountFields {
        for name in mounts.split(separator: ",") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { names.insert(trimmed) }
        }
    }
    return names
}

private func field(_ name: String, in text: String) -> [String]? {
    var values: [String] = []
    for line in contentLines(text) {
        guard let object = JSONLine.parse(line), let value = object.field(name) else { return nil }
        values.append(value)
    }
    return values
}

private func contentLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
}

private struct JSONLine {
    var values: [String: String]

    static func parse(_ line: String) -> JSONLine? {
        guard let data = line.data(using: .utf8), let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any] else { return nil }
        var values: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String { values[key] = string }
        }
        return JSONLine(values: values)
    }

    func field(_ name: String) -> String? { values[name] }
}
