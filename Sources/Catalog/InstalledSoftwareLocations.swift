import SharedKernel

/// Folders where installed apps and tools keep the software they run on: app support folders, editor extensions, tool
/// settings. Dependencies found there belong to that software, not to a project, so the scan rules leave them alone.
public enum InstalledSoftwareLocations {
    private static let dataVolume = "/System/Volumes/Data"

    /// Inside home: `Library`, `Applications`, and hidden folders other than the worktrees agent tools keep there.
    /// Outside home: everything except the shared temporary folders.
    public static func contains(_ path: CanonicalPath, home: CanonicalPath) -> Bool {
        let parts = lowered(path)
        let homeParts = lowered(home)
        if parts == homeParts { return false }
        guard parts.count > homeParts.count, Array(parts.prefix(homeParts.count)) == homeParts else {
            return !isTemporary(parts)
        }
        let first = parts[homeParts.count]
        if first == "library" || first == "applications" { return true }
        guard first.hasPrefix(".") else { return false }
        return !isInsideAgentWorktree(path, home: home)
    }

    private static func isTemporary(_ parts: [String]) -> Bool {
        let prefixes: [[String]] = [["private", "tmp"], ["private", "var", "folders"], ["tmp"], ["var", "folders"]]
        return prefixes.contains { parts.count > $0.count && Array(parts.prefix($0.count)) == $0 }
    }

    private static func isInsideAgentWorktree(_ path: CanonicalPath, home: CanonicalPath) -> Bool {
        var current: CanonicalPath? = path
        while let folder = current {
            if AgentLocations.isAgentWorktree(folder, home: home) { return true }
            current = folder.parent
        }
        return false
    }

    private static func lowered(_ path: CanonicalPath) -> [String] {
        var raw = path.raw
        if raw == dataVolume { raw = "/" } else if raw.hasPrefix(dataVolume + "/") { raw = String(raw.dropFirst(dataVolume.count)) }
        return raw.split(separator: "/").map { $0.lowercased() }
    }
}
