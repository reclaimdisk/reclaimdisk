import CoreGraphics
import Inventory
import SharedKernel

public struct TreemapCell: Identifiable, Equatable {
    public enum Content: Equatable {
        case node(Node)
        /// "Files in this folder": the folder's own files, beside its subfolders.
        case ownFiles(of: Node)
    }

    /// path.raw + "#aggregate" for aggregates, path.raw + "#files" for own files; unique per layout.
    public let id: String
    public let content: Content
    /// 1...3 below the current node.
    public let depth: Int
    public let rect: CGRect
    public let label: CellLabel

    public var showsLabel: Bool { label.showsName }

    /// The node this cell stands for (for own files: the folder that holds them).
    public var node: Node {
        switch content {
        case .node(let node), .ownFiles(of: let node): node
        }
    }

    public var isOwnFiles: Bool { if case .ownFiles = content { true } else { false } }
}

/// How a cell's label fits its rectangle.
public struct CellLabel: Equatable, Sendable {
    public let showsName: Bool
    /// The size shows only where it fits beside or below the name, so it never wraps or clips.
    public let showsSize: Bool
    /// Name above size (two lines); otherwise one line.
    public let isStacked: Bool

    static let hidden = CellLabel(showsName: false, showsSize: false, isStacked: false)
}

public enum NestedTreemap {
    /// Up to three levels below `node`: depth-1 groups get a 20 pt header and depth-2 groups a 16 pt header.
    /// A node with ownTakesUp > 0 and children gets an extra ownFiles cell weighted by ownTakesUp, so proportions are true.
    public static func cells(for node: Node, in rect: CGRect) -> [TreemapCell] {
        var result: [TreemapCell] = []
        layout(node, in: rect, depth: 1, into: &result)
        return result
    }

    /// The node a click on `cell` opens: a depth-3 cell opens its depth-2 parent; then, if that target has no
    /// children, its parent instead; depth-1 cells open themselves if they have children. Nil when nothing opens.
    public static func openTarget(for cell: TreemapCell, in cells: [TreemapCell]) -> Node? {
        guard let target = cell.depth == 3 ? parent(of: cell, in: cells) : cell else { return nil }
        if case .node(let node) = target.content, !node.isAggregate, !node.children.isEmpty { return node }
        guard target.depth > 1, let parentCell = parent(of: target, in: cells), case .node(let node) = parentCell.content else { return nil }
        return node
    }

    private static func parent(of cell: TreemapCell, in cells: [TreemapCell]) -> TreemapCell? {
        let parentPath = cell.isOwnFiles ? cell.node.path : cell.node.path.parent
        return cells.first { candidate in
            guard candidate.depth == cell.depth - 1, case .node(let node) = candidate.content else { return false }
            return !node.isAggregate && node.path == parentPath
        }
    }

    private static func entries(of node: Node) -> [(content: TreemapCell.Content, bytes: UInt64)] {
        var entries: [(content: TreemapCell.Content, bytes: UInt64)] = node.children
            .filter { $0.footprint.takesUp > .zero }
            .map { (.node($0), $0.footprint.takesUp.bytes) }
        if node.ownTakesUp > .zero, !node.children.isEmpty {
            entries.append((.ownFiles(of: node), node.ownTakesUp.bytes))
        }
        return entries
    }

    private static func layout(_ node: Node, in rect: CGRect, depth: Int, into result: inout [TreemapCell]) {
        let entries = entries(of: node)
        let placed = TreemapLayout.squarify(entries.enumerated().map { TreemapItem(id: $0.offset, weight: Double($0.element.bytes)) }, in: rect)
        for (index, cellRect) in placed where cellRect.width >= 0.5 && cellRect.height >= 0.5 {
            let content = entries[index].content
            let slot = result.count
            result.append(TreemapCell(id: "", content: content, depth: depth, rect: cellRect, label: .hidden))   // replaced below
            var isGroup = false
            if depth < 3, case .node(let child) = content, !child.isAggregate, !child.children.isEmpty {
                let header: CGFloat = depth == 1 ? 20 : 16
                let inner = CGRect(x: cellRect.minX + 1, y: cellRect.minY + header,
                                   width: max(0, cellRect.width - 2), height: max(0, cellRect.height - header - 1))
                let before = result.count
                layout(child, in: inner, depth: depth + 1, into: &result)
                isGroup = result.count > before
            }
            result[slot] = TreemapCell(id: id(for: content), content: content, depth: depth, rect: cellRect,
                                       label: label(depth: depth, isGroup: isGroup, size: cellRect.size))
        }
    }

    private static func id(for content: TreemapCell.Content) -> String {
        switch content {
        case .node(let node): node.isAggregate ? node.path.raw + "#aggregate" : node.path.raw
        case .ownFiles(of: let node): node.path.raw + "#files"
        }
    }

    /// Names need 46×16 pt (depth 1), 50×14 pt (depth-2 group headers) or 58×32 pt (depth 2 and 3 leaves). Leaves at
    /// least 32 pt tall stack the size under the name; everything else gets one line, with the size only from 110 pt wide.
    public static func label(depth: Int, isGroup: Bool, size: CGSize) -> CellLabel {
        let showsName = switch (depth, isGroup) {
        case (1, _): size.width >= 46 && size.height >= 16
        case (2, true): size.width >= 50 && size.height >= 14
        default: size.width >= 58 && size.height >= 32
        }
        guard showsName else { return .hidden }
        let isStacked = !isGroup && size.height >= 32
        return CellLabel(showsName: true, showsSize: isStacked || size.width >= 110, isStacked: isStacked)
    }
}
