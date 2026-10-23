import SharedKernel

/// An immutable snapshot of one volume (or one folder on it) at one time.
public struct Scan: Hashable, Sendable {
    /// The Data volume's mount, e.g. /System/Volumes/Data.
    public let volumeMountPath: CanonicalPath
    public let root: Node
    public let disk: DiskLayout
    public let startedAt: Instant
    public let finishedAt: Instant
    /// Sorted by path.
    public let unreadable: [UnreadableArea]
    public let scannedUniqueBytes: ByteCount
    public let isWholeVolume: Bool

    public init(
        volumeMountPath: CanonicalPath, root: NodeDraft, disk: DiskLayout, startedAt: Instant, finishedAt: Instant,
        unreadable: [UnreadableArea], scannedUniqueBytes: ByteCount, isWholeVolume: Bool, classifier: KindClassifier
    ) throws(InventoryError) {
        guard finishedAt >= startedAt else { throw .finishBeforeStart }
        self.volumeMountPath = volumeMountPath
        self.root = try Self.node(from: root, parentKind: nil, classifier: classifier)
        self.disk = disk
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.unreadable = unreadable.sorted { $0.path < $1.path }
        self.scannedUniqueBytes = scannedUniqueBytes
        self.isWholeVolume = isWholeVolume
    }

    /// Whole volume only: what the volume uses beyond what the scan could attribute.
    public var notReadable: ByteCount? {
        isWholeVolume ? disk.data.usedByVolume.subtractingClamped(scannedUniqueBytes) : nil
    }

    /// True when some folder is locked by macOS privacy (EPERM), which Full Disk Access can lift.
    public var needsFullDiskAccess: Bool { unreadable.contains { $0.reason == .notPermitted } }

    /// Own bytes summed by node kind. The takes-up figures add up to the root's takes-up.
    public func kindTotals() -> [Kind: KindTotal] {
        var totals: [Kind: KindTotal] = [:]
        var stack = [root]
        while let node = stack.popLast() {
            var total = totals[node.kind] ?? KindTotal(takesUp: .zero, freesAtLeast: .zero)
            total.takesUp += node.ownTakesUp
            total.freesAtLeast += node.ownFreesAtLeast
            totals[node.kind] = total
            stack.append(contentsOf: node.children)
        }
        return totals
    }

    private static func node(from draft: NodeDraft, parentKind: Kind?, classifier: KindClassifier) throws(InventoryError) -> Node {
        let kind = draft.isAggregate
            ? (draft.aggregateKind ?? parentKind ?? .other)
            : classifier.kind(for: draft.path, name: draft.name, markers: draft.markers, parentKind: parentKind)
        var children: [Node] = []
        children.reserveCapacity(draft.children.count)
        for child in draft.children {
            children.append(try node(from: child, parentKind: kind, classifier: classifier))
        }
        children.sort { ($0.footprint.takesUp, $1.name) > ($1.footprint.takesUp, $0.name) }
        var takesUp = draft.ownTakesUp, freesAtLeast = draft.ownFreesAtLeast
        for child in children {
            takesUp += child.footprint.takesUp
            freesAtLeast += child.footprint.freesAtLeast
        }
        guard freesAtLeast <= takesUp else { throw .freesExceedsTakesUp(draft.path) }
        let footprint = try Footprint(takesUp: takesUp, freesAtLeast: freesAtLeast)
        return Node(draft: draft, kind: kind, footprint: footprint, children: children)
    }
}
