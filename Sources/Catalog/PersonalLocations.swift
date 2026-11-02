import SharedKernel

/// Documents, Desktop and the other folders that hold a person's own files.
/// Compared case-insensitively. `/System/Volumes/Data/Users` and `/Users` are the same folders (a firmlink).
public enum PersonalLocations {
    private static let dataVolume = "/System/Volumes/Data"
    private static let relatives = [
        "documents", "desktop", "downloads", "pictures", "movies", "music",
        "library/mail", "library/messages", "library/mobile documents", "library/cloudstorage",
    ]

    public static func contains(_ path: CanonicalPath, home: CanonicalPath) -> Bool {
        let pathKey = comparisonKey(path)
        let homeKey = comparisonKey(home)
        for relative in relatives {
            let folder = homeKey == "/" ? "/" + relative : homeKey + "/" + relative
            if pathKey == folder || pathKey.hasPrefix(folder + "/") { return true }
        }
        return false
    }

    /// User-facing, lowercased form. Strips the Data volume prefix so a firmlink and its mount compare equal.
    private static func comparisonKey(_ path: CanonicalPath) -> String {
        let raw: String
        if path.raw == dataVolume {
            raw = "/"
        } else if path.raw.hasPrefix(dataVolume + "/") {
            raw = String(path.raw.dropFirst(dataVolume.count))
        } else {
            raw = path.raw
        }
        return raw.lowercased()
    }
}
