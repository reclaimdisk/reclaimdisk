import SharedKernel

public protocol Rule: Sendable {
    var id: RuleID { get }
    var title: String { get }
    func evaluate(_ context: RuleContext) -> RuleResult
}

public struct RuleContext: Sendable {
    public let scan: any ScanQuery
    public let home: CanonicalPath
    public let now: Instant

    public init(scan: any ScanQuery, home: CanonicalPath, now: Instant) {
        self.scan = scan
        self.home = home
        self.now = now
    }
}

public struct RuleResult: Sendable, Equatable {
    public var candidates: [Candidate]
    public var notes: [RuleNote]

    public init(candidates: [Candidate], notes: [RuleNote]) {
        self.candidates = candidates
        self.notes = notes
    }
}

public struct RuleNote: Hashable, Sendable {
    public enum Status: String, Sendable {
        case notApplicable = "not-applicable"
        case unknown
    }

    public let rule: RuleID
    public let status: Status
    public let reason: String

    public init(rule: RuleID, status: Status, reason: String) {
        self.rule = rule
        self.status = status
        self.reason = reason
    }
}
