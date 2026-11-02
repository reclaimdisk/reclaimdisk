import AppKit
import Application
import Catalog
import Inventory
import SharedKernel
import SwiftUI

/// Colors chosen so badge text and the blocked reason stay readable on both appearances.
private enum CleanupPalette {
    static func title(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0xF4F7FA : 0x121A22) }
    static func secondary(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0xC5D0DA : 0x3D4A57) }
    static func blocked(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0xFFC48A : 0x8F2D0B) }
    static func selected(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x8EE0B0 : 0x0E7A3D) }
    static func rowFill(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x1B232C : 0xF4F6F8) }
    static func separator(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x3A4854 : 0xD0D7DE) }

    static func badge(_ reclaimClass: ReclaimClass, _ scheme: ColorScheme) -> (foreground: Color, background: Color) {
        switch (reclaimClass, scheme) {
        case (.rebuildable, .dark): (color(0x042E18), color(0x8EE0B0))
        case (.rebuildable, _): (color(0xFFFFFF), color(0x0E7A3D))
        case (.toolManaged, .dark): (color(0x062848), color(0x9CC8FF))
        case (.toolManaged, _): (color(0xFFFFFF), color(0x0C4F92))
        case (_, .dark): (color(0x1A1612), color(0xE6D5C4))
        case (_, _): (color(0xFFFFFF), color(0x5C5348))
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(nsColor: NSColor(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        ))
    }
}

private enum CleanupEntry: Identifiable {
    case summary(String)
    case group(Kind, String, ByteCount)
    case candidate(Candidate)
    case notes
    case note(Int, RuleNote)

    var id: String {
        switch self {
        case .summary: "summary"
        case .group(let kind, _, _): "group-\(kind.rawValue)"
        case .candidate(let candidate): "candidate-\(candidate.id.rawValue)"
        case .notes: "notes"
        case .note(let index, _): "note-\(index)"
        }
    }

    static func rows(in list: CandidateList) -> [CleanupEntry] {
        var rows: [CleanupEntry] = [.summary(summary(list))]
        for group in CandidateGroups.make(list) {
            rows.append(.group(group.kind, group.title, group.selectedByDefaultFreesAtLeast))
            rows.append(contentsOf: group.candidates.map { .candidate($0) })
        }
        if !list.notes.isEmpty {
            rows.append(.notes)
            for (index, note) in list.notes.enumerated() { rows.append(.note(index, note)) }
        }
        return rows
    }

    /// The only total on the screen: what the rows selected by default free at least, and how many that is.
    private static func summary(_ list: CandidateList) -> String {
        let total = ByteText.down(CandidateGroups.selectedByDefaultFreesAtLeast(list))
        let count = CandidateGroups.selectedByDefaultCount(list)
        let items = count == 1 ? "item" : "items"
        return "Frees at least \(total) across \(count) \(items) selected by default"
    }
}

/// The list, laid out in full. The scrolling tab uses a lazy stack of the same rows.
struct CleanupContent: View {
    let list: CandidateList

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(CleanupEntry.rows(in: list)) { CleanupCell(entry: $0) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows a proposal in progress, the failure text, or the candidate list for one finished scan.
struct CleanupView: View {
    let scan: Scan
    let model: CandidatesModel
    @State private var proposedFor: Instant?

    var body: some View {
        Group {
            switch model.state {
            case .idle, .proposing:
                CleanupProgress()
            case .failed(let message):
                CleanupFailure(message: message)
            case .ready(let list):
                ScrollView {
                    // Lazy: a scan can propose hundreds of rows, and only the visible ones should be built.
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(CleanupEntry.rows(in: list)) { CleanupCell(entry: $0) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { proposeIfNeeded() }
        .onChange(of: scan.startedAt) { _, _ in proposeIfNeeded() }
    }

    /// One proposal per finished scan. Appearing again for the same scan does not start another.
    private func proposeIfNeeded() {
        guard proposedFor != scan.startedAt else { return }
        proposedFor = scan.startedAt
        model.propose(from: scan)
    }
}

private struct CleanupProgress: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding candidates…")
                .foregroundStyle(CleanupPalette.secondary(scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CleanupFailure: View {
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(message)
            .foregroundStyle(CleanupPalette.title(scheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
    }
}

private struct CleanupCell: View {
    let entry: CleanupEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch entry {
        case .summary(let sentence):
            Text(sentence)
                .font(.title3.weight(.semibold))
                .foregroundStyle(CleanupPalette.title(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .group(let kind, let title, let frees):
            GroupLine(kind: kind, title: title, frees: frees)
        case .candidate(let candidate):
            CandidateCleanupRow(candidate: candidate)
        case .notes:
            Text("Notes")
                .font(.headline)
                .foregroundStyle(CleanupPalette.title(scheme))
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .note(_, let note):
            NoteLine(note: note)
        }
    }
}

private struct GroupLine: View {
    let kind: Kind
    let title: String
    let frees: ByteCount
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(KindPalette.color(for: .kind(kind), scheme: scheme))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(CleanupPalette.title(scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Frees at least \(ByteText.down(frees))")
                .font(.subheadline)
                .foregroundStyle(CleanupPalette.secondary(scheme))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct NoteLine: View {
    let note: RuleNote
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.status(note.status))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CleanupPalette.title(scheme))
            Text(DisplayText.escaped(note.reason))
                .font(.caption)
                .foregroundStyle(CleanupPalette.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CleanupPalette.rowFill(scheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CleanupPalette.separator(scheme), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.status(note.status)). \(DisplayText.escaped(note.reason))")
    }

    private static func status(_ status: RuleNote.Status) -> String {
        switch status {
        case .notApplicable: "Not applicable"
        case .unknown: "Couldn't check"
        }
    }
}

private struct CandidateCleanupRow: View {
    let candidate: Candidate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let text = CandidateRowText(candidate)
        decorated(text)
    }

    @ViewBuilder private func decorated(_ text: CandidateRowText) -> some View {
        let row = contents(text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CleanupPalette.rowFill(scheme), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CleanupPalette.separator(scheme), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.accessibilityLabel)
        if case .path(let path) = candidate.target {
            row.contextMenu {
                Button("Reveal in Finder") { reveal(path) }
            }
            .accessibilityAction(named: "Reveal in Finder") { reveal(path) }
        } else {
            row
        }
    }

    private func contents(_ text: CandidateRowText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: text.isSelectedByDefault ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(text.isSelectedByDefault ? CleanupPalette.selected(scheme) : CleanupPalette.secondary(scheme))
                    .accessibilityHidden(true)
                Text(DisplayText.escaped(candidate.title))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(CleanupPalette.title(scheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(text.estimate)
                    .font(.caption)
                    .foregroundStyle(CleanupPalette.secondary(scheme))
                    .monospacedDigit()
                    .lineLimit(1)
                badge(text)
            }
            Text(DisplayText.escaped(text.target))
                .font(.caption.monospaced())
                .foregroundStyle(CleanupPalette.secondary(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.detail.isEmpty {
                Text(DisplayText.escaped(text.detail))
                    .font(.caption)
                    .foregroundStyle(CleanupPalette.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let blocked = text.blocked {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                    Text(DisplayText.escaped(blocked))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(CleanupPalette.blocked(scheme))
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(candidate.evidence.enumerated()), id: \.offset) { _, evidence in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(DisplayText.escaped(evidence.fact))
                                .font(.caption)
                                .foregroundStyle(CleanupPalette.title(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(Self.source(evidence.source))
                                .font(.caption2)
                                .foregroundStyle(CleanupPalette.secondary(scheme))
                        }
                    }
                }
                .padding(.top, 2)
            } label: {
                Text("Evidence").font(.caption).foregroundStyle(CleanupPalette.secondary(scheme))
            }
        }
    }

    private func badge(_ text: CandidateRowText) -> some View {
        let colors = CleanupPalette.badge(candidate.reclaimClass, scheme)
        return Text(text.badge)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(colors.foreground)
            .background(colors.background, in: Capsule())
    }

    private func reveal(_ path: CanonicalPath) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.raw)])
    }

    private static func source(_ source: EvidenceSource) -> String {
        switch source {
        case .scan: "From the scan"
        case .fileSystem: "From the file system"
        case .toolRecords(let tool): "From \(Self.capitalized(tool))"
        case .sessionRecords: "From session records"
        case .git: "From git"
        case .processTable: "From running processes"
        }
    }

    private static func capitalized(_ tool: String) -> String {
        guard let first = tool.first else { return tool }
        return first.uppercased() + tool.dropFirst()
    }
}
