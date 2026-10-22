/// What a candidate would clean: a path, or a resource owned by a tool (spec section 5).
public enum Target: Hashable, Sendable {
    case path(CanonicalPath)
    case toolResource(tool: String, identifier: String)
}
