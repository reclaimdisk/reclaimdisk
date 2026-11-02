@testable import AppFeature
import Catalog
import SharedKernel
import Testing

/// Nothing frees space a report-only candidate takes up, so its row shows what it takes up instead.
@Test func aReportOnlyRowShowsWhatItTakesUp() throws {
    let disk = try Candidate(
        rule: RuleID("docker-disk-file")!, title: "Docker disk file", kind: .docker,
        target: .path(CanonicalPath("/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")!),
        reclaimClass: .reportOnly, estimate: try Estimate.measured(freesAtLeast: .zero, takesUp: ByteCount(39_353_884_672)),
        evidence: [Evidence(fact: "Docker's disk file takes up 36.7 GiB of its 160.0 GiB maximum.", source: .fileSystem,
                            observedAt: Instant(nanosecondsSince1970: 0))!],
        recovery: nil, action: nil, newestChange: nil, isInstalledRuntime: false, blockedReason: nil,
        explanation: "Docker manages this file."
    )
    #expect(CandidateRowText(disk).estimate == "Takes up 36.7 GiB")
}
