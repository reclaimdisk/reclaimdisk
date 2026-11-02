import Catalog
import Darwin
import Foundation
import SharedKernel

/// Playwright's browser cache. `PLAYWRIGHT_BROWSERS_PATH` when it is set, otherwise `~/Library/Caches/ms-playwright`.
struct LivePlaywrightRecords: PlaywrightRecords {
    var cacheFolder: URL

    init(cacheFolder: URL) {
        self.cacheFolder = cacheFolder
    }

    static func defaultCacheFolder(home: CanonicalPath) -> URL {
        if let raw = ProcessInfo.processInfo.environment["PLAYWRIGHT_BROWSERS_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let path = home.appending("Library")?.appending("Caches")?.appending("ms-playwright")?.raw
            ?? "/Library/Caches/ms-playwright"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func read() -> PlaywrightReading {
        let cache = cacheFolder
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: cache.path, isDirectory: &isDirectory) else { return .notInstalled }
        guard isDirectory.boolValue, let cachePath = canonical(cache) else {
            return .unreadable("Playwright's browser folder can't be read.")
        }
        let found: [PlaywrightBuild]
        switch builds(in: cache) {
        case .failure(let reason): return .unreadable(reason)
        case .found(let builds): found = builds
        }
        let needed: [PlaywrightRequirement]
        switch requirements(in: cache) {
        case .failure(let reason): return .unreadable(reason)
        case .found(let requirements): needed = requirements
        }
        return .read(PlaywrightSnapshot(cacheFolder: cachePath, builds: found, requirements: needed))
    }

    private func builds(in cache: URL) -> BuildRead {
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) }
        catch { return .failure("Can't read \(cache.path).") }
        var builds: [PlaywrightBuild] = []
        for child in children {
            guard let parsed = buildName(child.lastPathComponent) else { continue }
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let folder = canonical(child) else { continue }
            builds.append(PlaywrightBuild(
                browser: parsed.browser, revision: parsed.revision, folder: folder, size: allocatedBytes(of: child)
            ))
        }
        return .found(builds)
    }

    /// `<name>-<revision>` with an all-digit revision. Underscores in the name are hyphens, matching `browsers.json`.
    private func buildName(_ name: String) -> (browser: String, revision: String)? {
        guard let dash = name.lastIndex(of: "-") else { return nil }
        let revision = name[name.index(after: dash)...]
        guard !revision.isEmpty, revision.unicodeScalars.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        let browser = name[..<dash]
        guard !browser.isEmpty else { return nil }
        return (browser.replacingOccurrences(of: "_", with: "-"), String(revision))
    }

    private func requirements(in cache: URL) -> RequirementRead {
        let links = cache.appendingPathComponent(".links", isDirectory: true)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: links.path, isDirectory: &isDirectory) else { return .found([]) }
        guard isDirectory.boolValue else { return .failure("Playwright's installation links can't be read.") }
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: links, includingPropertiesForKeys: nil) }
        catch { return .failure("Can't read \(links.path).") }
        var requirements: [PlaywrightRequirement] = []
        var seen = Set<RequirementKey>()
        for file in files {
            switch installation(at: file, cache: cache) {
            case .skip: continue
            case .failure(let reason): return .failure(reason)
            case .found(let root):
                switch browsers(at: root) {
                case .skip: continue
                case .failure(let reason): return .failure(reason)
                case .found(let rows):
                    for row in rows where seen.insert(RequirementKey(installation: row.installation, browser: row.browser, revision: row.revision)).inserted {
                        requirements.append(row)
                    }
                }
            }
        }
        return .found(requirements)
    }

    /// A link file's text is a path. A trailing newline is not part of it. A relative path is tried from the
    /// working directory and from the cache folder. A path that is gone adds nothing.
    private func installation(at file: URL, cache: URL) -> LinkRead {
        var info = stat()
        if lstat(file.path, &info) != 0 { return errno == ENOENT ? .skip : .failure("Can't read \(file.path).") }
        let kind = info.st_mode & S_IFMT
        if kind == S_IFDIR { return .skip }
        if kind != S_IFREG && kind != S_IFLNK { return .skip }
        let data: Data
        do { data = try Data(contentsOf: file) } catch { return .failure("Can't read \(file.path).") }
        guard let text = String(data: data, encoding: .utf8) else { return .failure("Can't read \(file.path).") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skip }
        for path in pathCandidates(trimmed, cache: cache) {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            return .found(URL(fileURLWithPath: path, isDirectory: true))
        }
        return .skip
    }

    private func pathCandidates(_ trimmed: String, cache: URL) -> [String] {
        if trimmed.hasPrefix("/") { return [normalize(absolute: trimmed)] }
        let workingDirectory = FileManager.default.currentDirectoryPath
        return [
            normalize(absolute: join(base: workingDirectory, relative: trimmed)),
            normalize(absolute: join(base: cache.path, relative: trimmed)),
        ]
    }

    private func browsers(at installation: URL) -> LinkReadList {
        let json = installation.appendingPathComponent("browsers.json")
        guard FileManager.default.fileExists(atPath: json.path) else { return .skip }
        guard let root = canonical(installation) else { return .failure("Can't read \(json.path).") }
        let data: Data
        do { data = try Data(contentsOf: json) } catch { return .failure("Can't read \(json.path).") }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { return .failure("Can't read \(json.path).") }
        guard let document = object as? [String: Any], let browsers = document["browsers"] as? [Any] else {
            return .failure("Can't read \(json.path).")
        }
        var rows: [PlaywrightRequirement] = []
        for entry in browsers {
            guard let browser = entry as? [String: Any],
                  let name = jsonString(browser["name"]),
                  let revision = jsonString(browser["revision"]) else {
                return .failure("Can't read \(json.path).")
            }
            rows.append(PlaywrightRequirement(installation: root, browser: name, revision: revision))
            if let overrides = browser["revisionOverrides"] {
                guard let table = overrides as? [String: Any] else { return .failure("Can't read \(json.path).") }
                for value in table.values {
                    guard let revision = jsonString(value) else { return .failure("Can't read \(json.path).") }
                    rows.append(PlaywrightRequirement(installation: root, browser: name, revision: revision))
                }
            }
        }
        return .found(rows)
    }

    /// Allocated bytes, each inode once. Nil when the folder can't be measured; the rule then uses the scan.
    private func allocatedBytes(of folder: URL) -> ByteCount? {
        let start = folder.resolvingSymlinksInPath()
        var total: UInt64 = 0
        var seen = Set<Inode>()
        var pending = [start]
        while let url = pending.popLast() {
            var info = stat()
            if lstat(url.path, &info) != 0 {
                if errno == ENOENT { continue }
                return nil
            }
            let inode = Inode(device: UInt64(info.st_dev), number: UInt64(info.st_ino))
            let kind = info.st_mode & S_IFMT
            if kind == S_IFDIR {
                guard seen.insert(inode).inserted else { continue }
                guard add(&total, blocks: info.st_blocks) else { return nil }
                let children: [URL]
                do { children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
                catch { return nil }
                pending.append(contentsOf: children)
                continue
            }
            guard seen.insert(inode).inserted else { continue }
            guard add(&total, blocks: info.st_blocks) else { return nil }
        }
        return ByteCount(total)
    }
}

private struct Inode: Hashable {
    var device: UInt64
    var number: UInt64
}

private struct RequirementKey: Hashable {
    var installation: CanonicalPath
    var browser: String
    var revision: String
}

private enum BuildRead {
    case failure(String)
    case found([PlaywrightBuild])
}

private enum RequirementRead {
    case failure(String)
    case found([PlaywrightRequirement])
}

private enum LinkRead {
    case skip
    case failure(String)
    case found(URL)
}

private enum LinkReadList {
    case skip
    case failure(String)
    case found([PlaywrightRequirement])
}

private func canonical(_ url: URL) -> CanonicalPath? {
    var path = url.resolvingSymlinksInPath().path
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return CanonicalPath(path)
}

private func jsonString(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}

private func join(base: String, relative: String) -> String {
    base == "/" ? "/" + relative : base + "/" + relative
}

private func normalize(absolute path: String) -> String {
    var parts: [String] = []
    for part in path.split(separator: "/") {
        if part == "." { continue }
        if part == ".." {
            if !parts.isEmpty { parts.removeLast() }
            continue
        }
        parts.append(String(part))
    }
    return "/" + parts.joined(separator: "/")
}

private func add(_ total: inout UInt64, blocks: Int64) -> Bool {
    guard blocks > 0 else { return true }
    let (bytes, overflowed) = UInt64(blocks).multipliedReportingOverflow(by: 512)
    guard !overflowed else { return false }
    let (sum, sumOverflowed) = total.addingReportingOverflow(bytes)
    guard !sumOverflowed else { return false }
    total = sum
    return true
}
