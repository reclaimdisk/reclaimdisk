import Application
import Catalog
import SharedKernel

/// The words one cleanup row shows. Pure: the same candidate always produces the same text.
struct CandidateRowText: Equatable {
    let target: String
    let estimate: String
    let badge: String
    let detail: String
    let blocked: String?
    let isSelectedByDefault: Bool
    let accessibilityLabel: String

    init(_ candidate: Candidate) {
        target = Self.target(candidate.target)
        estimate = Self.estimate(candidate)
        badge = Self.badge(candidate.reclaimClass)
        detail = Self.detail(candidate)
        blocked = candidate.blockedReason
        isSelectedByDefault = candidate.isPreselected
        accessibilityLabel = Self.label(
            title: candidate.title, target: target, estimate: estimate, badge: badge, detail: detail,
            blocked: blocked, selected: isSelectedByDefault, evidence: candidate.evidence
        )
    }

    private static func target(_ target: Target) -> String {
        switch target {
        case .path(let path): path.raw
        case .toolResource(let tool, let identifier): "\(capitalized(tool)): \(identifier)"
        }
    }

    /// A report-only candidate frees nothing by itself, so it shows what it takes up.
    private static func estimate(_ candidate: Candidate) -> String {
        let estimate = candidate.estimate
        return switch estimate.basis {
        case .measured where candidate.reclaimClass == .reportOnly:
            "Takes up \(ByteFormatting.string(estimate.takesUp ?? .zero, rounding: .nearest))"
        case .measured:
            "Frees at least \(ByteFormatting.string(estimate.freesAtLeast ?? .zero, rounding: .down))"
        case .toolReported(let tool):
            "\(capitalized(tool)) reports \(ByteFormatting.string(estimate.reported ?? .zero, rounding: .nearest))"
        case .unknown:
            "Size unknown"
        }
    }

    private static func badge(_ reclaimClass: ReclaimClass) -> String {
        switch reclaimClass {
        case .rebuildable: "Rebuildable"
        case .toolManaged: "Tool-managed"
        case .reportOnly: "Report only"
        case .never: "Never"
        }
    }

    /// Cleanable rows say how the bytes come back. A report-only row says why it is only a report.
    private static func detail(_ candidate: Candidate) -> String {
        switch candidate.reclaimClass {
        case .reportOnly:
            candidate.explanation ?? ""
        case .rebuildable, .toolManaged, .never:
            candidate.recovery.map { "Comes back with: \($0.text)" } ?? ""
        }
    }

    private static func label(
        title: String, target: String, estimate: String, badge: String, detail: String, blocked: String?, selected: Bool,
        evidence: [Evidence]
    ) -> String {
        var parts = [title, target, estimate, badge]
        if !detail.isEmpty { parts.append(detail) }
        if selected { parts.append("Selected by default") }
        if let blocked, !blocked.isEmpty { parts.append(blocked) }
        let facts = evidence.map(\.fact)
        if !facts.isEmpty { parts.append(facts.joined(separator: ". ")) }
        return parts.map(DisplayText.escaped).joined(separator: ". ")
    }

    private static func capitalized(_ tool: String) -> String {
        guard let first = tool.first else { return tool }
        return first.uppercased() + tool.dropFirst()
    }
}
