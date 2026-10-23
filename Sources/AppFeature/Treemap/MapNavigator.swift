import Inventory
import Observation
import SharedKernel

@MainActor @Observable
public final class MapNavigator {
    private var stack: [Node]

    public init(root: Node) { stack = [root] }

    public var current: Node { stack[stack.count - 1] }

    /// Root … current.
    public var breadcrumbs: [Node] { stack }

    /// No-op for nodes without children and for aggregates.
    public func open(_ node: Node) {
        guard !node.isAggregate, !node.children.isEmpty else { return }
        open(path: node.path)
    }

    public func up() {
        if stack.count > 1 { stack.removeLast() }
    }

    /// Walks from the root; no-op if the path isn't found or has no children.
    public func open(path: CanonicalPath) {
        var chain = [stack[0]]
        var node = stack[0]
        while node.path != path {
            guard let next = node.children.first(where: { !$0.isAggregate && path.isSameOrDescendant(of: $0.path) }) else { return }
            chain.append(next)
            node = next
        }
        guard !node.children.isEmpty else { return }
        stack = chain
    }
}
