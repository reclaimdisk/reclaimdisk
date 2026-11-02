import Catalog
import SharedKernel
import Testing

private let now = Instant(nanosecondsSince1970: 1_800_000_000_000_000_000)
private let folder = CanonicalPath("/Users/u/Projects/app/target")!
private let rust = RuleID("rust-build-folder")!

private func fact(_ text: String = "Holds CACHEDIR.TAG and .rustc_info.json", _ source: EvidenceSource = .scan) -> Evidence {
    Evidence(fact: text, source: source, observedAt: now)!
}

private func measured(_ atLeast: UInt64 = 10, _ takes: UInt64 = 20) -> Estimate {
    try! Estimate.measured(freesAtLeast: ByteCount(atLeast), takesUp: ByteCount(takes))
}

private func candidate(
    reclaimClass: ReclaimClass = .rebuildable, evidence: [Evidence]? = nil, recovery: Recovery? = Recovery("cargo build"),
    action: CandidateAction? = .deletePath(folder), isInstalledRuntime: Bool = false, blockedReason: String? = nil,
    explanation: String? = nil
) throws(CandidateError) -> Candidate {
    try Candidate(
        rule: rust, title: "Rust build folder", kind: .buildOutput, target: .path(folder), reclaimClass: reclaimClass,
        estimate: measured(), evidence: evidence ?? [fact()], recovery: recovery, action: action, newestChange: nil,
        isInstalledRuntime: isInstalledRuntime, blockedReason: blockedReason, explanation: explanation
    )
}

@Test func aCandidateNeedsAtLeastOneEvidence() {
    #expect(throws: CandidateError.noEvidence) { try candidate(evidence: []) }
}

@Test func aNeverTargetNeverBecomesACandidate() {
    #expect(throws: CandidateError.neverClass) { try candidate(reclaimClass: .never) }
}

@Test func aReportOnlyCandidateHasNoActionAndExplainsItself() throws {
    #expect(throws: CandidateError.reportOnlyHasAction) { try candidate(reclaimClass: .reportOnly, explanation: "Kept for review") }
    #expect(throws: CandidateError.missingExplanation) { try candidate(reclaimClass: .reportOnly, action: nil) }
    let report = try candidate(reclaimClass: .reportOnly, recovery: nil, action: nil, explanation: "No documented way to remove it")
    #expect(report.action == nil)
    #expect(report.isPreselected == false)
}

@Test func cleanableCandidatesNeedAnActionAndARecovery() {
    #expect(throws: CandidateError.missingAction) { try candidate(action: nil) }
    #expect(throws: CandidateError.missingRecovery) { try candidate(recovery: nil) }
}

@Test func anInstalledRuntimeNeedsEvidenceFromItsOwnTool() throws {
    #expect(throws: CandidateError.runtimeWithoutToolEvidence) { try candidate(isInstalledRuntime: true) }
    let runtime = try candidate(evidence: [fact("No project needs revision 1187", .toolRecords("playwright"))], isInstalledRuntime: true)
    #expect(runtime.isInstalledRuntime)
}

@Test func toolReportedEstimatesNeverClaimFreesAtLeast() throws {
    let docker = try Estimate.toolReported(tool: "docker", size: ByteCount(5_983_000_000))
    #expect(docker.freesAtLeast == nil)
    #expect(docker.takesUp == nil)
    #expect(docker.reported == ByteCount(5_983_000_000))
    #expect(docker.basis == .toolReported(tool: "docker"))
    #expect(throws: EstimateError.unnamedTool) { try Estimate.toolReported(tool: " ", size: .zero) }
    #expect(throws: EstimateError.freesMoreThanItTakesUp) { try Estimate.measured(freesAtLeast: ByteCount(21), takesUp: ByteCount(20)) }
    #expect(Estimate.unknown.basis == .unknown)
    #expect(Estimate.unknown.freesAtLeast == nil && Estimate.unknown.reported == nil)
}

@Test func theIdIsTheRulePlusTheTarget() throws {
    #expect(try candidate().id.rawValue == "rust-build-folder:/Users/u/Projects/app/target")
    let cache = try Candidate(
        rule: RuleID("docker-build-cache")!, title: "Docker build cache", kind: .docker,
        target: .toolResource(tool: "docker", identifier: "build-cache"), reclaimClass: .toolManaged,
        estimate: try .toolReported(tool: "docker", size: ByteCount(1)),
        evidence: [fact("Docker reports 1 B of build cache", .toolRecords("docker"))], recovery: Recovery("Rebuilt on the next build"),
        action: .toolCommand(ToolCommand(executable: "docker", arguments: ["builder", "prune", "-f"])!),
        newestChange: nil, isInstalledRuntime: false, blockedReason: nil, explanation: nil
    )
    #expect(cache.id.rawValue == "docker-build-cache:docker/build-cache")
    #expect(cache.isPreselected == false)   // tool-managed is never preselected
}

@Test func onlyUnblockedRebuildableCandidatesArePreselected() throws {
    #expect(try candidate().isPreselected)
    #expect(try candidate(blockedReason: "Changed in the last 24 hours").isPreselected == false)
}

@Test func ruleIdsAreLowercaseWordsJoinedByHyphens() {
    #expect(RuleID("rust-build-folder")?.rawValue == "rust-build-folder")
    #expect(RuleID("node-dependencies2") != nil)
    for bad in ["", "Rust", "a--b", "-a", "a-", "a b", "a:b", "a/b"] {
        #expect(RuleID(bad) == nil, "\(bad)")
    }
}

@Test func evidenceRecoveryAndCommandsAreNeverBlank() {
    #expect(Evidence(fact: " ", source: .scan, observedAt: now) == nil)
    #expect(Recovery("") == nil)
    #expect(ToolCommand(executable: "", arguments: []) == nil)
}
