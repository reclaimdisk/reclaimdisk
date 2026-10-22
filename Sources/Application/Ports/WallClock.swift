import SharedKernel

public protocol WallClock: Sendable {
    func now() -> Instant
}
