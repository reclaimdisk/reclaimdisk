import Catalog
import Foundation
import SharedKernel

/// Pure parsers for `simctl`'s JSON. A value that is not the expected shape fails the whole result.
enum SimctlOutput {
    /// Top-level object whose values are runtime objects, sorted by identifier.
    static func runtimes(_ json: String) -> [SimulatorRuntime]? {
        guard let objects = decode(json, as: [String: RuntimeObject].self) else { return nil }
        var runtimes: [SimulatorRuntime] = []
        for object in objects.values {
            guard let runtime = runtime(from: object) else { return nil }
            runtimes.append(runtime)
        }
        return runtimes.sorted { $0.identifier < $1.identifier }
    }

    static func devices(_ json: String) -> [SimulatorDevice]? {
        guard let list = decode(json, as: DeviceList.self) else { return nil }
        var devices: [SimulatorDevice] = []
        for (runtimeIdentifier, objects) in list.devices {
            for object in objects {
                devices.append(SimulatorDevice(
                    udid: object.udid, name: object.name, runtimeIdentifier: runtimeIdentifier,
                    isAvailable: object.isAvailable, dataSize: object.dataPathSize.map(ByteCount.init)
                ))
            }
        }
        return devices
    }
}

/// The asset folder is the prefix through the first component that ends in `.asset`, whatever hash it uses.
private func assetFolder(in path: String?) -> CanonicalPath? {
    guard let path, path.hasPrefix("/") else { return nil }
    var kept: [String] = []
    for part in path.split(separator: "/") {
        let name = String(part)
        kept.append(name)
        if name.hasSuffix(".asset") {
            return CanonicalPath("/" + kept.joined(separator: "/"))
        }
    }
    return nil
}

private func runtime(from object: RuntimeObject) -> SimulatorRuntime? {
    let lastUsedAt: Instant?
    if let text = object.lastUsedAt {
        guard let instant = instant(fromISO8601: text) else { return nil }
        lastUsedAt = instant
    } else {
        lastUsedAt = nil
    }
    let asset = assetFolder(in: object.path) ?? assetFolder(in: object.parentMountPath)
    return SimulatorRuntime(
        identifier: object.identifier, runtimeIdentifier: object.runtimeIdentifier, version: object.version,
        lastUsedAt: lastUsedAt, size: object.sizeBytes.map(ByteCount.init), isDeletable: object.deletable, assetFolder: asset
    )
}

private struct RuntimeObject: Decodable {
    var deletable: Bool
    var identifier: String
    var lastUsedAt: String?
    var parentMountPath: String?
    var path: String?
    var runtimeIdentifier: String?
    var sizeBytes: UInt64?
    var version: String
}

private struct DeviceList: Decodable {
    var devices: [String: [DeviceObject]]
}

private struct DeviceObject: Decodable {
    var udid: String
    var name: String
    var isAvailable: Bool
    var dataPathSize: UInt64?
}

private func decode<T: Decodable>(_ json: String, as type: T.Type) -> T? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

/// `yyyy-MM-ddTHH:mm:ss[.fraction]Z` or a numeric offset. The offset decides the instant.
private func instant(fromISO8601 text: String) -> Instant? {
    let pieces = text.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
    guard pieces.count == 2 else { return nil }
    let date = pieces[0].split(separator: "-", omittingEmptySubsequences: false)
    guard date.count == 3, let year = Int(date[0]), let month = Int(date[1]), let day = Int(date[2]) else { return nil }
    guard (1...9999).contains(year), (1...12).contains(month), (1...daysInMonth(year: year, month: month)).contains(day) else {
        return nil
    }
    let timeText = pieces[1]
    guard let zoneIndex = timeText.lastIndex(where: { $0 == "Z" || $0 == "z" || $0 == "+" || $0 == "-" }) else { return nil }
    let clock = timeText[..<zoneIndex]
    let zone = timeText[zoneIndex...]
    let clockParts = clock.split(separator: ":", omittingEmptySubsequences: false)
    guard clockParts.count == 3, let hour = Int(clockParts[0]), let minute = Int(clockParts[1]) else { return nil }
    let secondParts = clockParts[2].split(separator: ".", omittingEmptySubsequences: false)
    guard (secondParts.count == 1 || secondParts.count == 2), let second = Int(secondParts[0]) else { return nil }
    guard (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second) else { return nil }
    let fraction: Int64
    if secondParts.count == 2 {
        guard let parsed = fractionNanoseconds(secondParts[1]) else { return nil }
        fraction = parsed
    } else {
        fraction = 0
    }
    let offset: Int64
    if zone == "Z" || zone == "z" {
        offset = 0
    } else if zone.first == "+" || zone.first == "-" {
        guard let parsed = zoneOffset(zone) else { return nil }
        offset = parsed
    } else {
        return nil
    }
    guard let days = daysSinceUnixEpoch(year: year, month: month, day: day) else { return nil }
    let local = days * 86_400 + Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
    let (utc, overflowed) = local.subtractingReportingOverflow(offset)
    guard !overflowed else { return nil }
    return Instant(seconds: utc, nanoseconds: fraction)
}

private func fractionNanoseconds(_ fraction: Substring) -> Int64? {
    guard !fraction.isEmpty, fraction.allSatisfy(\.isNumber) else { return nil }
    let digits = fraction.prefix(9)
    guard let number = Int64(digits) else { return nil }
    var scale: Int64 = 1
    for _ in digits.count..<9 {
        scale *= 10
    }
    return number * scale
}

private func zoneOffset(_ zone: Substring) -> Int64? {
    let sign: Int64 = zone.first == "+" ? 1 : -1
    let body = zone.dropFirst()
    let hourPart: Substring
    let minutePart: Substring
    if body.count == 5, body.dropFirst(2).first == ":" {
        hourPart = body.prefix(2)
        minutePart = body.suffix(2)
    } else if body.count == 4 {
        hourPart = body.prefix(2)
        minutePart = body.suffix(2)
    } else {
        return nil
    }
    guard let hour = Int(hourPart), let minute = Int(minutePart), (0...23).contains(hour), (0...59).contains(minute) else {
        return nil
    }
    return sign * (Int64(hour) * 3600 + Int64(minute) * 60)
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
