import SharedKernel

/// Two sizes for one node (spec section 5): "takes up" (allocated, each inode once) and
/// "frees at least" (bytes deleting it would certainly free). Invariant: freesAtLeast <= takesUp.
public struct Footprint: Hashable, Sendable {
    public let takesUp: ByteCount
    public let freesAtLeast: ByteCount

    public init(takesUp: ByteCount, freesAtLeast: ByteCount) throws(InventoryError) {
        guard freesAtLeast <= takesUp else { throw .freesExceedsTakesUp(.root) }
        self.takesUp = takesUp
        self.freesAtLeast = freesAtLeast
    }

    private init(unchecked takesUp: ByteCount, _ freesAtLeast: ByteCount) {
        self.takesUp = takesUp
        self.freesAtLeast = freesAtLeast
    }

    public static let zero = Footprint(unchecked: .zero, .zero)
}

/// Plain per-kind sums, deliberately not validated: hard-link credit can land on an
/// ancestor of a different kind, so one kind's frees can exceed its takes.
public struct KindTotal: Hashable, Sendable {
    public var takesUp: ByteCount
    public var freesAtLeast: ByteCount

    public init(takesUp: ByteCount, freesAtLeast: ByteCount) {
        self.takesUp = takesUp
        self.freesAtLeast = freesAtLeast
    }
}
