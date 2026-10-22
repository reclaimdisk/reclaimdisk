import Inventory
import SharedKernel

extension NodeDraft {
    /// The child with this name; fails the test run loudly when missing.
    public func child(_ name: String) -> NodeDraft {
        guard let match = children.first(where: { $0.name == name }) else {
            preconditionFailure("no child named \(name) under \(path); children: \(children.map(\.name))")
        }
        return match
    }

    /// Own bytes plus all descendants.
    public var totalTakesUp: ByteCount { children.reduce(ownTakesUp) { $0 + $1.totalTakesUp } }
    public var totalFreesAtLeast: ByteCount { children.reduce(ownFreesAtLeast) { $0 + $1.totalFreesAtLeast } }
}
