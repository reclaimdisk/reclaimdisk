import Application
import Catalog
import SharedKernel
import Testing
@testable import CLI

/// Reasons and recovery text can carry names from the disk (a worktree's ignored file); none of it reaches the terminal raw.
@Test func textOutputEscapesEveryFieldItPrints() throws {
    let target = CanonicalPath("/Users/u/Projects/app/.worktrees/x")!
    let candidate = try Candidate(
        rule: RuleID("agent-worktrees")!, title: "Agent worktree", kind: .agentSessions, target: .path(target),
        reclaimClass: .toolManaged, estimate: try Estimate.measured(freesAtLeast: ByteCount(1), takesUp: ByteCount(1)),
        evidence: [Evidence(fact: "Linked Git worktree.", source: .git, observedAt: Instant(nanosecondsSince1970: 0))!],
        recovery: Recovery("git worktree add \u{1B}[31mred"),
        action: .toolCommand(ToolCommand(executable: "git", arguments: ["worktree", "remove", target.raw])!), newestChange: nil,
        isInstalledRuntime: false, blockedReason: "It holds ignored files that aren't build output: \u{1B}]0;title\u{7}", explanation: nil
    )
    let text = CandidateReport.text(CandidateList(candidates: [candidate], notes: [], generatedAt: Instant(nanosecondsSince1970: 0)))
    #expect(!text.unicodeScalars.contains { $0.value == 0x1B || $0.value == 0x07 })
}
