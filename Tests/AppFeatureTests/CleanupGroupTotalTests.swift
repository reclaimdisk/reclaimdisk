@testable import AppFeature
import SharedKernel
import Testing

/// A group with nothing selected by default says so rather than "Frees at least 0 MiB" beside a tool's own size.
@Test func aGroupTotalSaysWhenNothingIsSelectedByDefault() {
    #expect(CandidateGroups.totalText(.zero) == "Nothing selected by default")
    #expect(CandidateGroups.totalText(ByteCount(12 * 1_073_741_824)) == "Frees at least 12.0 GiB")
}
