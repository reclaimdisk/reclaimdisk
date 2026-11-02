import Catalog
import SharedKernel

/// Pure parsers for an Android virtual device's `config.ini` and for system-image package names.
enum AndroidOutput {
    /// `image.sysdir.1` relative to the SDK root. A trailing slash is not part of the folder.
    static func imageFolder(fromConfig config: String, sdkRoot: CanonicalPath) -> CanonicalPath? {
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "image.sysdir.1" else { continue }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            value = value.split(separator: "\\").joined(separator: "/")
            while value.hasSuffix("/") { value.removeLast() }
            guard !value.isEmpty else { return nil }
            if value.hasPrefix("/") { return CanonicalPath(value) }
            return appending(sdkRoot, relative: value)
        }
        return nil
    }

    /// The SDK-relative folder, with `/` written as `;` (`system-images;android-35;google_apis;arm64-v8a`).
    static func package(forImageFolder folder: CanonicalPath, sdkRoot: CanonicalPath) -> String? {
        let prefix = sdkRoot.raw == "/" ? "/" : sdkRoot.raw + "/"
        guard folder.raw.hasPrefix(prefix) else { return nil }
        let relative = folder.raw.dropFirst(prefix.count)
        guard !relative.isEmpty else { return nil }
        return relative.split(separator: "/").joined(separator: ";")
    }
}

private func appending(_ root: CanonicalPath, relative: String) -> CanonicalPath? {
    var path = root
    for part in relative.split(separator: "/") {
        guard let next = path.appending(String(part)) else { return nil }
        path = next
    }
    return path == root ? nil : path
}
