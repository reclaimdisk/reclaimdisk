/// What a folder is for, as shown on the map. Raw values are the JSON names.
public enum Kind: String, CaseIterable, Sendable {
    case buildOutput = "build-output"
    case caches
    case docker
    case agentSessions = "agent-sessions"
    case developerTools = "developer-tools"
    case apps
    case projectSource = "project-source"
    case personalFiles = "personal-files"
    case macOSData = "macos-data"
    case other
    case notReadable = "not-readable"
}
