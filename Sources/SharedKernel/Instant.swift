/// A wall-clock moment, in nanoseconds since 1970-01-01 UTC. Standard library only, so no `Date`.
public struct Instant: Hashable, Comparable, Sendable {
    public let nanosecondsSince1970: Int64

    public init(nanosecondsSince1970: Int64) { self.nanosecondsSince1970 = nanosecondsSince1970 }

    public init(seconds: Int64, nanoseconds: Int64) {
        self.init(nanosecondsSince1970: seconds * 1_000_000_000 + nanoseconds)
    }

    public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.nanosecondsSince1970 < rhs.nanosecondsSince1970 }
}
