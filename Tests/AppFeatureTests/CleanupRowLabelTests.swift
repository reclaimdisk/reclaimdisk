@testable import AppFeature
import Catalog
import SharedKernel
import Testing

/// VoiceOver reads a row as one label; sentences that already end with a period must not gain a second one.
@Test func aRowLabelJoinsSentencesWithOnePeriod() throws {
    let rust = try Candidate(
        rule: RuleID("rust-build-folder")!, title: "Rust build folder", kind: .buildOutput,
        target: .path(CanonicalPath("/Users/u/Projects/app/target")!), reclaimClass: .rebuildable,
        estimate: try Estimate.measured(freesAtLeast: ByteCount(1_073_741_824), takesUp: ByteCount(1_073_741_824)),
        evidence: [
            Evidence(fact: "Holds CACHEDIR.TAG and .rustc_info.json.", source: .scan, observedAt: Instant(nanosecondsSince1970: 0))!,
            Evidence(fact: "The parent folder holds Cargo.toml.", source: .scan, observedAt: Instant(nanosecondsSince1970: 0))!,
        ],
        recovery: Recovery("cargo build"), action: .deletePath(CanonicalPath("/Users/u/Projects/app/target")!), newestChange: nil,
        isInstalledRuntime: false, blockedReason: "Changed in the last 24 hours. Wait until no build uses it.", explanation: nil
    )
    let label = CandidateRowText(rust).accessibilityLabel
    #expect(!label.contains(".."))
    #expect(label.contains("Wait until no build uses it. Holds CACHEDIR.TAG and .rustc_info.json. The parent folder holds Cargo.toml"))
}
