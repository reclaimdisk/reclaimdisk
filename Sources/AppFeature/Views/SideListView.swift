import Inventory
import SharedKernel
import SwiftUI

/// The current folder's contents, ranked by takes up. This is also the accessible form of the map.
struct SideListRows: View {
    let navigator: MapNavigator
    @Environment(\.colorScheme) private var scheme

    private struct Row: Identifiable {
        let id: String
        let node: Node
        let isOwnFiles: Bool
        var takes: ByteCount { isOwnFiles ? node.ownTakesUp : node.footprint.takesUp }
        var frees: ByteCount { isOwnFiles ? node.ownFreesAtLeast : node.footprint.freesAtLeast }
        var name: String { isOwnFiles ? "Files in this folder" : node.name }
    }

    private var rows: [Row] {
        let current = navigator.current
        var rows = current.children.map { Row(id: $0.isAggregate ? $0.path.raw + "#aggregate" : $0.path.raw, node: $0, isOwnFiles: false) }
        if current.ownTakesUp > .zero, !current.children.isEmpty {
            rows.append(Row(id: current.path.raw + "#files", node: current, isOwnFiles: true))
        }
        return rows.sorted { ($0.takes, $1.name) > ($1.takes, $0.name) }
    }

    var body: some View {
        let rows = rows
        let largest = max(1, rows.first.map { Double($0.takes.bytes) } ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            Text(navigator.current.name).font(.headline).lineLimit(1).truncationMode(.middle)
            ForEach(rows) { row in
                Group {
                    if !row.isOwnFiles, navigator.canOpen(row.node) {
                        // A real Button, so VoiceOver can open folders from this list (it is the accessible form of the map).
                        Button { navigator.open(row.node) } label: { content(of: row, largest: largest) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this folder in the map")
                    } else {
                        // Not a button: VoiceOver mustn't offer an action that does nothing.
                        content(of: row, largest: largest).accessibilityElement(children: .ignore).accessibilityAddTraits(.isStaticText)
                    }
                }
                .contextMenu {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.node.path.raw)]) }
                        .disabled(!row.isOwnFiles && row.node.isAggregate)
                }
                .accessibilityLabel("\(row.name), takes up \(ByteText.nearest(row.takes)), frees at least \(ByteText.down(row.frees)), \(KindPalette.title(for: .kind(row.node.kind)))")
            }
        }
    }

    private func content(of row: Row, largest: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(KindPalette.color(for: .kind(row.node.kind), scheme: scheme)).frame(width: 10, height: 10)
                Text(row.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ByteText.nearest(row.takes)).monospacedDigit()
            }
            HStack(spacing: 6) {
                GeometryReader { geometry in
                    Capsule().fill(KindPalette.color(for: .kind(row.node.kind), scheme: scheme))
                        .frame(width: max(2, geometry.size.width * Double(row.takes.bytes) / largest))
                }
                .frame(height: 4)
                Text("frees ≥ \(ByteText.down(row.frees))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}
