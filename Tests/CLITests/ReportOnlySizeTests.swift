import Application
import Catalog
import SharedKernel
import Testing
@testable import CLI

/// Nothing frees space a report-only candidate takes up, so its line shows what it takes up instead.
@Test func aReportOnlyLineShowsWhatItTakesUp() throws {
    let disk = try Candidate(
        rule: RuleID("docker-disk-file")!, title: "Docker disk file", kind: .docker,
        target: .path(CanonicalPath("/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")!),
        reclaimClass: .reportOnly, estimate: try Estimate.measured(freesAtLeast: .zero, takesUp: ByteCount(39_353_884_672)),
        evidence: [Evidence(fact: "Docker's disk file takes up 36.7 GiB of its 160.0 GiB maximum.", source: .fileSystem,
                            observedAt: Instant(nanosecondsSince1970: 0))!],
        recovery: nil, action: nil, newestChange: nil, isInstalledRuntime: false, blockedReason: nil,
        explanation: "Docker manages this file."
    )
    let text = CandidateReport.text(CandidateList(candidates: [disk], notes: [], generatedAt: Instant(nanosecondsSince1970: 0)))
    #expect(text.contains("takes up 36.7 GiB  report-only  Docker disk file"))
    #expect(!text.contains("frees at least 0"))
}
