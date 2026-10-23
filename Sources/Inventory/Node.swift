import SharedKernel

/// A validated folder or large file in a scan. Only `Scan.init` creates nodes.
public struct Node: Hashable, Sendable {
    public let name: String
    public let path: CanonicalPath
    public let kind: Kind
    /// Own bytes plus all children, validated: freesAtLeast <= takesUp.
    public let footprint: Footprint
    public let ownTakesUp: ByteCount
    public let ownFreesAtLeast: ByteCount
    /// nil when the folder holds nothing with a date (an empty folder).
    public let newestChange: Instant?
    public let markers: Set<String>
    public let isFile: Bool
    public let isAggregate: Bool
    /// Sorted: takes up descending, then name ascending.
    public let children: [Node]

    init(draft: NodeDraft, kind: Kind, footprint: Footprint, children: [Node]) {
        name = draft.name
        path = draft.path
        self.kind = kind
        self.footprint = footprint
        ownTakesUp = draft.ownTakesUp
        ownFreesAtLeast = draft.ownFreesAtLeast
        newestChange = draft.newestChange
        markers = draft.markers
        isFile = draft.isFile
        isAggregate = draft.isAggregate
        self.children = children
    }
}
