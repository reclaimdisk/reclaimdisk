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

    private static func withoutDataVolume(_ path: CanonicalPath) -> CanonicalPath {
        if path.raw == dataVolume { return .root }
        if path.raw.hasPrefix(dataVolume + "/"), let stripped = CanonicalPath(String(path.raw.dropFirst(dataVolume.count))) {
            return stripped
        }
        return path
    }
}
