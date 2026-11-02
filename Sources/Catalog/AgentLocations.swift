import SharedKernel

/// Scratch space an agent is using right now. A scan rule leaves it alone.
public enum AgentLocations {
    private static let dataVolume = "/System/Volumes/Data"

    /// `/private/tmp/claude-<digits>` and everything inside it.
    public static func isAgentTemp(_ path: CanonicalPath) -> Bool {
        let components = withoutDataVolume(path).components
        guard components.count >= 3, components[0] == "private", components[1] == "tmp" else { return false }
        let name = components[2]
        let prefix = "claude-"
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        return !suffix.isEmpty && suffix.unicodeScalars.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// A checkout an agent tool keeps next to the main repository. Direct child of `.worktrees`, of
    /// `.claude/worktrees`, of `~/.codex/worktrees/<id>`, or of `~/.cursor/worktrees/<repo>`.
    public static func isAgentWorktree(_ path: CanonicalPath, home: CanonicalPath) -> Bool {
        let components = withoutDataVolume(path).components
        guard components.count >= 2 else { return false }
        let parentName = components[components.count - 2]
        if parentName == ".worktrees" { return true }
        if components.count >= 3, parentName == "worktrees", components[components.count - 3] == ".claude" { return true }
        let homeComponents = withoutDataVolume(home).components
        guard components.count == homeComponents.count + 4,
              Array(components.prefix(homeComponents.count)) == homeComponents else { return false }
        let tool = components[homeComponents.count]
        return (tool == ".codex" || tool == ".cursor") && components[homeComponents.count + 1] == "worktrees"
    }

    private static func withoutDataVolume(_ path: CanonicalPath) -> CanonicalPath {
        if path.raw == dataVolume { return .root }
        if path.raw.hasPrefix(dataVolume + "/"), let stripped = CanonicalPath(String(path.raw.dropFirst(dataVolume.count))) {
            return stripped
        }
        return path
    }
}
