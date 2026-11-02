import SharedKernel

/// Where a fact was observed.
public enum EvidenceSource: Hashable, Sendable {
    case scan
    case fileSystem
    case toolRecords(String)
    case sessionRecords
    case git
    case processTable
}

/// One fact that supports a candidate. A blank fact is refused: a candidate with nothing to show is not evidence.
public struct Evidence: Hashable, Sendable {
    public let fact: String
    public let source: EvidenceSource
    public let observedAt: Instant

    public init?(fact: String, source: EvidenceSource, observedAt: Instant) {
        guard !BlankText.isBlank(fact) else { return nil }
        self.fact = fact
        self.source = source
        self.observedAt = observedAt
    }
}
