import Testing
@testable import SharedKernel

@Test func subtractingClampsAtZero() {
    #expect(ByteCount(3).subtractingClamped(ByteCount(5)) == .zero)
    #expect(ByteCount(5).subtractingClamped(ByteCount(3)) == ByteCount(2))
}

@Test func additionAndUnits() {
    var total = ByteCount(1) + ByteCount(2)
    total += ByteCount(3)
    #expect(total == ByteCount(6))
    #expect(ByteCount.mebibyte.bytes == 1_048_576)
    #expect(ByteCount.gibibyte.bytes == 1_073_741_824)
    #expect(ByteCount.zero < ByteCount(1))
}

@Test func instantOrdersByTime() {
    #expect(Instant(seconds: 1, nanoseconds: 5) == Instant(nanosecondsSince1970: 1_000_000_005))
    #expect(Instant(nanosecondsSince1970: 1) < Instant(nanosecondsSince1970: 2))
}

@Test func kindRawValuesMatchTheJSONSchema() {
    #expect(Kind.buildOutput.rawValue == "build-output")
    #expect(Kind.agentSessions.rawValue == "agent-sessions")
    #expect(Kind.notReadable.rawValue == "not-readable")
    #expect(Kind.caches.rawValue == "caches")
    #expect(ReclaimClass.toolManaged.rawValue == "tool-managed")
}

// Final review, Important 2: APFS clamps very old dates to the lowest 64-bit nanosecond value; converting must not trap.
@Test func instantSaturatesInsteadOfOverflowing() {
    #expect(Instant(seconds: -9_223_372_037, nanoseconds: 0) == Instant(nanosecondsSince1970: .min))
    #expect(Instant(seconds: 9_223_372_037, nanoseconds: 0) == Instant(nanosecondsSince1970: .max))
    #expect(Instant(seconds: -9_223_372_036, nanoseconds: -854_775_808) == Instant(nanosecondsSince1970: .min))
    #expect(Instant(seconds: 9_223_372_036, nanoseconds: 854_775_808) == Instant(nanosecondsSince1970: .max))
}
