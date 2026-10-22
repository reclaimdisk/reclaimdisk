import Application
import Darwin
import SharedKernel

public struct SystemWallClock: WallClock {
    public init() {}

    public func now() -> Instant {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return Instant(seconds: Int64(time.tv_sec), nanoseconds: Int64(time.tv_nsec))
    }
}
