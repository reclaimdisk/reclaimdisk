import SharedKernel

public enum UnreadableReason: String, Sendable {
    case permissionDenied = "permission-denied"
    case notPermitted = "not-permitted"
    case pathTooLong = "path-too-long"
    case other
}

/// One folder that couldn't be read; its subtree wasn't read either.
public struct UnreadableArea: Hashable, Sendable {
    public let path: CanonicalPath
    public let reason: UnreadableReason

    public init(path: CanonicalPath, reason: UnreadableReason) {
        self.path = path
        self.reason = reason
    }
}
