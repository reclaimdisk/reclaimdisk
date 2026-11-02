import SharedKernel

public enum CandidateError: Error, Equatable, Sendable {
    case noEvidence
    case neverClass
    case reportOnlyHasAction
    case missingExplanation
    case missingAction
    case missingRecovery
    case runtimeWithoutToolEvidence
}

/// "<rule>:<path>" for a path, "<rule>:<tool>/<identifier>" for a tool resource.
public struct CandidateID: Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func < (lhs: CandidateID, rhs: CandidateID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One proposed cleanup. Creating it checks the class rules; it does not touch the disk.
public struct Candidate: Hashable, Sendable, Identifiable {
    public let id: CandidateID
    public let rule: RuleID
    public let title: String
    public let kind: Kind
    public let target: Target
    public let reclaimClass: ReclaimClass
    public let estimate: Estimate
    public let evidence: [Evidence]
    public let recovery: Recovery?
    public let action: CandidateAction?
    public let newestChange: Instant?
    public let isInstalledRuntime: Bool
    public let blockedReason: String?
    public let explanation: String?

    /// Rebuildable candidates are offered already chosen, unless something (a recent change) blocks them.
    public var isPreselected: Bool { reclaimClass == .rebuildable && blockedReason == nil }

    public init(
        rule: RuleID, title: String, kind: Kind, target: Target, reclaimClass: ReclaimClass, estimate: Estimate,
        evidence: [Evidence], recovery: Recovery?, action: CandidateAction?, newestChange: Instant?,
        isInstalledRuntime: Bool, blockedReason: String?, explanation: String?
    ) throws(CandidateError) {
        if evidence.isEmpty { throw .noEvidence }
        switch reclaimClass {
        case .never:
            throw .neverClass
        case .reportOnly:
            if action != nil { throw .reportOnlyHasAction }
            if explanation.map(BlankText.isBlank) ?? true { throw .missingExplanation }
        case .rebuildable, .toolManaged:
            if action == nil { throw .missingAction }
            if recovery == nil { throw .missingRecovery }
        }
        if isInstalledRuntime && !evidence.contains(where: Self.isToolRecord) { throw .runtimeWithoutToolEvidence }

        self.id = Self.makeID(rule: rule, target: target)
        self.rule = rule
        self.title = title
        self.kind = kind
        self.target = target
        self.reclaimClass = reclaimClass
        self.estimate = estimate
        self.evidence = evidence
        self.recovery = recovery
        self.action = action
        self.newestChange = newestChange
        self.isInstalledRuntime = isInstalledRuntime
        self.blockedReason = blockedReason
        self.explanation = explanation
    }

    private static func isToolRecord(_ evidence: Evidence) -> Bool {
        if case .toolRecords = evidence.source { return true }
        return false
    }

    private static func makeID(rule: RuleID, target: Target) -> CandidateID {
        switch target {
        case .path(let path):
            CandidateID("\(rule.rawValue):\(path.raw)")
        case .toolResource(let tool, let identifier):
            CandidateID("\(rule.rawValue):\(tool)/\(identifier)")
        }
    }
}
