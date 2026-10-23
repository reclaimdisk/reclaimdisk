import AppKit
import Inventory
import SharedKernel
import SwiftUI

struct MapView: View {
    @State private var navigator: MapNavigator

    init(scan: Scan) { _navigator = State(initialValue: MapNavigator(root: scan.root)) }

    var body: some View {
        HStack(spacing: 0) {
            TreemapPane(navigator: navigator).padding(16)
            Divider()
            ScrollView { SideListRows(navigator: navigator).padding(12) }
                .frame(width: 320)
                .accessibilityLabel("Contents of \(navigator.current.name)")
        }
    }
}

/// Breadcrumbs, the treemap and the hover line.
struct TreemapPane: View {
    let navigator: MapNavigator
    @State private var hovered: TreemapCell?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            breadcrumbs
            GeometryReader { geometry in
                let cells = NestedTreemap.cells(for: navigator.current, in: CGRect(origin: .zero, size: geometry.size))
                ZStack(alignment: .topLeading) {
                    ForEach(cells) { cell in
                        CellView(cell: cell, scheme: scheme)
                            .frame(width: cell.rect.width, height: cell.rect.height)
                            .offset(x: cell.rect.minX, y: cell.rect.minY)
                            .onTapGesture {
                                if let target = NestedTreemap.openTarget(for: cell, in: cells) { navigator.open(target) }
                            }
                            .onHover { inside in hovered = inside ? cell : (hovered == cell ? nil : hovered) }
                            .contextMenu { RevealButton(cell: cell) }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .accessibilityHidden(true)   // the side list is the accessible form of the map
            Text(hoverText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            ForEach(Array(navigator.breadcrumbs.enumerated()), id: \.offset) { index, node in
                if index > 0 { Text("/").foregroundStyle(.secondary) }
                Button(node.name) { navigator.open(path: node.path) }
                    .buttonStyle(.link)
                    .disabled(index == navigator.breadcrumbs.count - 1)
            }
            Spacer()
            Button("Up") { navigator.up() }.disabled(navigator.breadcrumbs.count < 2)
        }
    }

    private var hoverText: String {
        guard let cell = hovered else { return " " }
        let node = cell.node
        let name = cell.isOwnFiles ? "Files in this folder" : node.name
        let takes = cell.isOwnFiles ? node.ownTakesUp : node.footprint.takesUp
        let frees = cell.isOwnFiles ? node.ownFreesAtLeast : node.footprint.freesAtLeast
        return "\(name) · \(node.path.raw) · takes up \(ByteText.nearest(takes)) · frees at least \(ByteText.down(frees)) · \(KindPalette.title(for: .kind(node.kind)))"
    }
}

private struct CellView: View {
    let cell: TreemapCell
    let scheme: ColorScheme

    /// Depth-1 and depth-2 folders with subfolders draw their children below a header line.
    private var isGroupHeader: Bool {
        cell.depth < 3 && !cell.isOwnFiles && !cell.node.isAggregate && !cell.node.children.isEmpty
    }

    var body: some View {
        let node = cell.node
        let fill = KindPalette.color(for: .kind(node.kind), scheme: scheme)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(cell.isOwnFiles || node.isAggregate ? fill.opacity(0.75) : fill)
            Rectangle().strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.9), lineWidth: cell.depth == 1 ? 1.5 : 0.5)
            if cell.showsLabel {
                let name = Text(cell.isOwnFiles ? "Files in this folder" : node.name).font(.system(size: 11, weight: .semibold))
                let size = Text(ByteText.nearest(cell.isOwnFiles ? node.ownTakesUp : node.footprint.takesUp)).font(.system(size: 10)).monospacedDigit()
                Group {
                    if isGroupHeader {   // one line, so it fits the 20/16 pt header above the nested cells
                        HStack(spacing: 6) { name.lineLimit(1); size }
                    } else {
                        VStack(alignment: .leading, spacing: 0) { name.lineLimit(1); size }
                    }
                }
                .foregroundStyle(KindPalette.labelColor(scheme: scheme))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
    }
}

/// "Reveal in Finder": disabled for aggregates; for own files it reveals the folder.
struct RevealButton: View {
    let cell: TreemapCell

    var body: some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cell.node.path.raw)])
        }
        .disabled(!cell.isOwnFiles && cell.node.isAggregate)
    }
}
