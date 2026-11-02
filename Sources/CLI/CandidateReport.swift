import Application
import Catalog
import Foundation
import SharedKernel

/// Formats a candidate list as JSON schema 1 or as plain text. Pure: no I/O.
enum CandidateReport {
    static func json(_ list: CandidateList, scanRoot: CanonicalPath) throws -> String {
        let document: [String: Any] = [
            "schemaVersion": 1,
            "scanRoot": scanRoot.raw,
            "generatedAt": iso8601(list.generatedAt),
            "candidates": list.candidates.map(candidate),
            "notes": list.notes.map { ["rule": $0.rule.rawValue, "status": $0.status.rawValue, "reason": $0.reason] },
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func text(_ list: CandidateList) -> String {
        var lines: [String] = []
        let grouped = Dictionary(grouping: list.candidates, by: \.kind)
        for kind in Kind.allCases {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            if !lines.isEmpty { lines.append("") }
            lines.append(KindTitles.title(for: kind))
            for candidate in group {
                lines.append("  " + row(candidate))
                if let blocked = candidate.blockedReason { lines.append("  " + DisplayText.escaped(blocked)) }
            }
        }
        if !list.notes.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Notes")
            for note in list.notes {
                lines.append("  \(note.rule.rawValue) (\(note.status.rawValue)): \(DisplayText.escaped(note.reason))")
            }
        }
        let total = list.candidates.reduce(ByteCount.zero) { sum, candidate in
            guard candidate.isPreselected, let frees = candidate.estimate.freesAtLeast else { return sum }
            return sum + frees
        }
        if !lines.isEmpty { lines.append("") }
        lines.append("Frees at least: \(ByteFormatting.string(total, rounding: .down))")
        return lines.joined(separator: "\n")
    }

    private static func row(_ candidate: Candidate) -> String {
        let detail = DisplayText.escaped(candidate.recovery?.text ?? candidate.explanation ?? "")
        return [estimateText(candidate), candidate.reclaimClass.rawValue, DisplayText.escaped(candidate.title), targetText(candidate.target), detail]
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    /// A report-only candidate frees nothing by itself, so it shows what it takes up.
    private static func estimateText(_ candidate: Candidate) -> String {
        let estimate = candidate.estimate
        return switch estimate.basis {
        case .measured where candidate.reclaimClass == .reportOnly:
            "takes up \(ByteFormatting.string(estimate.takesUp ?? .zero, rounding: .nearest))"
        case .measured:
            "frees at least \(ByteFormatting.string(estimate.freesAtLeast ?? .zero, rounding: .down))"
        case .toolReported(let tool):
            "\(displayedTool(tool)) reports \(ByteFormatting.string(estimate.reported ?? .zero, rounding: .nearest))"
        case .unknown:
            "size unknown"
        }
    }

    private static func displayedTool(_ tool: String) -> String {
        guard let first = tool.first else { return tool }
        return first.uppercased() + tool.dropFirst()
    }

    private static func targetText(_ target: Target) -> String {
        switch target {
        case .path(let path): DisplayText.escaped(path.raw)
        case .toolResource(let tool, let identifier): DisplayText.escaped("\(tool)/\(identifier)")
        }
    }

    private static func candidate(_ candidate: Candidate) -> [String: Any] {
        [
            "id": candidate.id.rawValue,
            "rule": candidate.rule.rawValue,
            "title": candidate.title,
            "kind": candidate.kind.rawValue,
            "class": candidate.reclaimClass.rawValue,
            "target": target(candidate.target),
            "estimate": estimate(candidate.estimate),
            "evidence": candidate.evidence.map(evidence),
            "recovery": candidate.recovery.map { $0.text as Any } ?? NSNull(),
            "explanation": candidate.explanation.map { $0 as Any } ?? NSNull(),
            "action": candidate.action.map { action($0) as Any } ?? NSNull(),
            "newestChange": candidate.newestChange.map { iso8601($0) as Any } ?? NSNull(),
            "preselected": candidate.isPreselected,
            "blockedReason": candidate.blockedReason.map { $0 as Any } ?? NSNull(),
        ]
    }

    private static func target(_ target: Target) -> [String: Any] {
        switch target {
        case .path(let path): ["path": path.raw]
        case .toolResource(let tool, let identifier): ["tool": tool, "identifier": identifier]
        }
    }

    /// Inapplicable byte fields are omitted. A present null would not read back as an absent key.
    private static func estimate(_ estimate: Estimate) -> [String: Any] {
        switch estimate.basis {
        case .measured:
            ["basis": "measured", "freesAtLeast": number(estimate.freesAtLeast ?? .zero), "takesUp": number(estimate.takesUp ?? .zero)]
        case .toolReported(let tool):
            ["basis": "tool-reported", "tool": tool, "reported": number(estimate.reported ?? .zero)]
        case .unknown:
            ["basis": "unknown"]
        }
    }

    private static func evidence(_ evidence: Evidence) -> [String: Any] {
        ["fact": evidence.fact, "source": source(evidence.source), "observedAt": iso8601(evidence.observedAt)]
    }

    private static func source(_ source: EvidenceSource) -> String {
        switch source {
        case .scan: "scan"
        case .fileSystem: "file-system"
        case .toolRecords(let tool): "tool:\(tool)"
        case .sessionRecords: "session-records"
        case .git: "git"
        case .processTable: "process-table"
        }
    }

    private static func action(_ action: CandidateAction) -> [String: Any] {
        switch action {
        case .deletePath(let path):
            ["type": "delete", "path": path.raw]
        case .toolCommand(let command):
            ["type": "command", "command": [command.executable] + command.arguments]
        case .deleteStale(let path, let patterns, let untouchedForSeconds):
            ["type": "delete-stale", "path": path.raw, "patterns": patterns, "untouchedForSeconds": NSNumber(value: untouchedForSeconds)]
        }
    }

    private static func number(_ count: ByteCount) -> Any {
        Int(exactly: count.bytes).map { $0 as Any } ?? NSNumber(value: count.bytes)
    }

    private static func iso8601(_ instant: Instant) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: Double(instant.nanosecondsSince1970) / 1_000_000_000))
    }
}
