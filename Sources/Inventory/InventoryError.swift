import SharedKernel

public enum InventoryError: Error, Equatable, Sendable {
    /// A node's total "frees at least" exceeded its total "takes up".
    case freesExceedsTakesUp(CanonicalPath)
    case availableExceedsTotal
    case usedExceedsTotal
    case finishBeforeStart
}
