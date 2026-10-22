import Application
import Foundation
import SharedKernel

/// A clock that advances by a fixed step on every call.
public final class FakeClock: WallClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Int64
    private let step: Int64

    public init(start: Instant = Instant(nanosecondsSince1970: 0), stepNanoseconds: Int64 = 1_000_000) {
        current = start.nanosecondsSince1970
        step = stepNanoseconds
    }

    public func now() -> Instant {
        lock.withLock {
            defer { current += step }
            return Instant(nanosecondsSince1970: current)
        }
    }
}
