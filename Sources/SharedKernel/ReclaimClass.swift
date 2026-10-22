/// How a candidate may be cleaned (spec section 5).
public enum ReclaimClass: String, CaseIterable, Sendable {
    case rebuildable
    case toolManaged = "tool-managed"
    case reportOnly = "report-only"
    case never
}
