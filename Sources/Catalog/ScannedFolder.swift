import SharedKernel

/// One kept folder from a finished scan, as a rule sees it. `freesAtLeast` never exceeds `takesUp`.
public struct ScannedFolder: Hashable, Sendable {
    public let path: CanonicalPath
    public let kind: Kind
    public let takesUp: ByteCount
    public let freesAtLeast: ByteCount
    public let newestChange: Instant?
    public let markers: Set<String>
    public let parentMarkers: Set<String>

    public init?(
        path: CanonicalPath, kind: Kind, takesUp: ByteCount, freesAtLeast: ByteCount, newestChange: Instant?,
        markers: Set<String>, parentMarkers: Set<String>
    ) {
        guard freesAtLeast <= takesUp else { return nil }
        self.path = path
        self.kind = kind
        self.takesUp = takesUp
        self.freesAtLeast = freesAtLeast
        self.newestChange = newestChange
        self.markers = markers
        self.parentMarkers = parentMarkers
    }

    public var name: String { path.lastComponent }
}
