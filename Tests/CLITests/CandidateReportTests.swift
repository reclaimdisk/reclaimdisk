import Application
import Catalog
import Foundation
import SharedKernel
import Testing
@testable import CLI

private let now = Instant(nanosecondsSince1970: 1_800_000_000_000_000_000)
private let appTarget = CanonicalPath("/Users/u/Projects/app/target")!

private func list() throws -> CandidateList {
    let rust = try Candidate(
        rule: RuleID("rust-build-folder")!, title: "Rust build folder", kind: .buildOutput, target: .path(appTarget),
        reclaimClass: .rebuildable, estimate: try .measured(freesAtLeast: ByteCount(900), takesUp: ByteCount(1_000)),
        evidence: [Evidence(fact: "Holds CACHEDIR.TAG and .rustc_info.json", source: .scan, observedAt: now)!],
        recovery: Recovery("cargo build"), action: .deletePath(appTarget), newestChange: now, isInstalledRuntime: false,
        blockedReason: "Changed in the last 24 hours. Wait until no build uses it.", explanation: nil
    )
    let docker = try Candidate(
        rule: RuleID("docker-build-cache")!, title: "Docker build cache", kind: .docker,
        target: .toolResource(tool: "docker", identifier: "build-cache"), reclaimClass: .toolManaged,
        estimate: try .toolReported(tool: "docker", size: ByteCount(5_983_000_000)),
        evidence: [Evidence(fact: "Docker reports 5.983GB of build cache", source: .toolRecords("docker"), observedAt: now)!],
        recovery: Recovery("Rebuilt on the next build"),
        action: .toolCommand(ToolCommand(executable: "docker", arguments: ["builder", "prune", "-f"])!), newestChange: nil,
        isInstalledRuntime: false, blockedReason: nil, explanation: nil
    )
    return CandidateList(
        candidates: [rust, docker],
        notes: [RuleNote(rule: RuleID("android-images")!, status: .notApplicable, reason: "The Android SDK isn't installed")],
        generatedAt: now
    )
}

private func object(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

@Test func candidatesJsonCarriesSchemaOneAndEveryField() throws {
    let root = try object(try CandidateReport.json(try list(), scanRoot: CanonicalPath("/Users/u/Projects")!))
    #expect(root["schemaVersion"] as? Int == 1)
    #expect(root["scanRoot"] as? String == "/Users/u/Projects")
    let candidates = try #require(root["candidates"] as? [[String: Any]])
    #expect(candidates.count == 2)

    let rust = candidates[0]
    #expect(rust["id"] as? String == "rust-build-folder:/Users/u/Projects/app/target")
    #expect(rust["rule"] as? String == "rust-build-folder")
    #expect(rust["kind"] as? String == "build-output")
    #expect(rust["class"] as? String == "rebuildable")
    #expect((rust["target"] as? [String: Any])?["path"] as? String == "/Users/u/Projects/app/target")
    let estimate = try #require(rust["estimate"] as? [String: Any])
    #expect(estimate["basis"] as? String == "measured")
    #expect(estimate["freesAtLeast"] as? Int == 900)
    #expect(estimate["takesUp"] as? Int == 1_000)
    #expect((rust["action"] as? [String: Any])?["type"] as? String == "delete")
    #expect((rust["action"] as? [String: Any])?["path"] as? String == "/Users/u/Projects/app/target")
    #expect(rust["recovery"] as? String == "cargo build")
    #expect(rust["preselected"] as? Bool == false)
    #expect(rust["blockedReason"] as? String == "Changed in the last 24 hours. Wait until no build uses it.")
    let evidence = try #require(rust["evidence"] as? [[String: Any]])
    #expect(evidence.first?["fact"] as? String == "Holds CACHEDIR.TAG and .rustc_info.json")
    #expect(evidence.first?["source"] as? String == "scan")
    #expect(evidence.first?["observedAt"] as? String != nil)

    let docker = candidates[1]
    #expect((docker["target"] as? [String: Any])?["tool"] as? String == "docker")
    #expect((docker["target"] as? [String: Any])?["identifier"] as? String == "build-cache")
    let reported = try #require(docker["estimate"] as? [String: Any])
    #expect(reported["basis"] as? String == "tool-reported")
    #expect(reported["tool"] as? String == "docker")
    #expect(reported["reported"] as? Int == 5_983_000_000)
    #expect(reported["freesAtLeast"] == nil)
    #expect((docker["action"] as? [String: Any])?["type"] as? String == "command")
    #expect((docker["action"] as? [String: Any])?["command"] as? [String] == ["docker", "builder", "prune", "-f"])
    #expect((docker["evidence"] as? [[String: Any]])?.first?["source"] as? String == "tool:docker")

    let note = try #require((root["notes"] as? [[String: Any]])?.first)
    #expect(note["rule"] as? String == "android-images")
    #expect(note["status"] as? String == "not-applicable")
    #expect(note["reason"] as? String == "The Android SDK isn't installed")
}

@Test func candidatesTextShowsTargetsBlockedReasonsAndWhoReportedASize() throws {
    let text = CandidateReport.text(try list())
    #expect(text.contains("/Users/u/Projects/app/target"))
    #expect(text.contains("Changed in the last 24 hours. Wait until no build uses it."))
    #expect(text.contains("Docker reports"))
    #expect(text.contains("cargo build"))
    #expect(text.contains("The Android SDK isn't installed"))
}

@Test func candidatesCommandParsesKindAndJson() throws {
    let parsed = try ReclaimDiskCommand.parseAsRoot(["candidates", "--kind", "build-output", "--json"])
    let command = try #require(parsed as? CandidatesCommand)
    #expect(command.kind == .buildOutput)
    #expect(command.json)
    #expect(throws: (any Error).self) { try ReclaimDiskCommand.parseAsRoot(["candidates", "--kind", "junk"]) }
}
