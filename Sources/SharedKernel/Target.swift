/// What a candidate would clean: a path, or a resource owned by a tool.
public enum Target: Hashable, Sendable {
    case path(CanonicalPath)
    case toolResource(tool: String, identifier: String)
}
