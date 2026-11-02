import SharedKernel

/// What a later cleanup could do. Nothing in the catalog performs it.
public enum CandidateAction: Hashable, Sendable {
    case deletePath(CanonicalPath)
    case toolCommand(ToolCommand)
    case deleteStale(in: CanonicalPath, patterns: [String], untouchedForSeconds: Int64)
}
