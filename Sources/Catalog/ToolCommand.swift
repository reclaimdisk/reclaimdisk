/// A command that would maintain a tool-owned resource. Describing it does not run it.
public struct ToolCommand: Hashable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init?(executable: String, arguments: [String]) {
        guard !BlankText.isBlank(executable) else { return nil }
        self.executable = executable
        self.arguments = arguments
    }
}
