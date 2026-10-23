import SharedKernel

/// A node as the scanner builds it, before `Scan.init` validates it and assigns kinds.
public struct NodeDraft: Sendable, Equatable {
    public var name: String
    /// User-facing path.
    public var path: CanonicalPath
    /// This node's own files, not its children.
    public var ownTakesUp: ByteCount
    /// May exceed `ownTakesUp` (hard-link credit); totals may not.
    public var ownFreesAtLeast: ByteCount
    public var newestChange: Instant
    public var markers: Set<String>
    public var isFile: Bool
    public var isAggregate: Bool
    /// Set exactly when `isAggregate`.
    public var aggregateKind: Kind?
    public var children: [NodeDraft]

    public init(
        name: String, path: CanonicalPath, ownTakesUp: ByteCount, ownFreesAtLeast: ByteCount, newestChange: Instant,
        markers: Set<String>, isFile: Bool, isAggregate: Bool, aggregateKind: Kind?, children: [NodeDraft]
    ) {
        self.name = name
        self.path = path
        self.ownTakesUp = ownTakesUp
        self.ownFreesAtLeast = ownFreesAtLeast
        self.newestChange = newestChange
        self.markers = markers
        self.isFile = isFile
        self.isAggregate = isAggregate
        self.aggregateKind = aggregateKind
        self.children = children
    }
}
