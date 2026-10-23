/// A wall-clock moment, in nanoseconds since 1970-01-01 UTC. Standard library only, so no `Date`.
public struct Instant: Hashable, Comparable, Sendable {
    public let nanosecondsSince1970: Int64

    public init(nanosecondsSince1970: Int64) { self.nanosecondsSince1970 = nanosecondsSince1970 }

    /// Saturates at the Int64 range instead of trapping: APFS reports dates before about 1677 as the lowest value.
    public init(seconds: Int64, nanoseconds: Int64) {
        let (scaled, overflowed) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflowed else {
            self.init(nanosecondsSince1970: seconds < 0 ? .min : .max)
            return
        }
        let (sum, sumOverflowed) = scaled.addingReportingOverflow(nanoseconds)
        self.init(nanosecondsSince1970: sumOverflowed ? (nanoseconds < 0 ? .min : .max) : sum)
    }

    public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.nanosecondsSince1970 < rhs.nanosecondsSince1970 }
}
