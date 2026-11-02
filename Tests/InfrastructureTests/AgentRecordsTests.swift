import Catalog
import Foundation
import SharedKernel
import Testing
@testable import Infrastructure

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-records-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private func write(_ text: String, to url: URL, modified: Date? = nil) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
}

private func canonical(_ url: URL) -> CanonicalPath { CanonicalPath(url.resolvingSymlinksInPath().path)! }

@Test func claudeTranscriptsGiveTheSessionItsTempFolderLastActivityAndWorkingDirectories() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appendingPathComponent(".claude-work/projects/-Users-u-Projects-app")
    let recent = Date(timeIntervalSince1970: 1_799_999_000)
    try write("""
    {"type":"user","cwd":"/Users/u/Projects/app","sessionId":"aaaa"}
    {"type":"assistant","cwd":"/Users/u/Projects/app/.worktrees/feat","sessionId":"aaaa"}
    not json at all
    """, to: config.appendingPathComponent("aaaa.jsonl"), modified: recent)
    let records = ClaudeSessionReader(configDirectories: [root.appendingPathComponent(".claude-work")], tempRoot: CanonicalPath("/private/tmp/claude-501")!)
    let sessions = try #require(records.read(now: Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000), activityWindowSeconds: 86_400))
    #expect(sessions.count == 1)
    let session = try #require(sessions.first)
    #expect(session.tool == "claude")
    #expect(session.id == "aaaa")
    #expect(session.tempFolder == CanonicalPath("/private/tmp/claude-501/-Users-u-Projects-app/aaaa"))
    #expect(session.lastActivity == Instant(nanosecondsSince1970: 1_799_999_000 * 1_000_000_000))
    #expect(session.workingDirectories == [CanonicalPath("/Users/u/Projects/app")!, CanonicalPath("/Users/u/Projects/app/.worktrees/feat")!])
}

@Test func codexRolloutsGiveTheSessionsWorkingDirectory() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("""
    {"timestamp":"2026-10-24T19:17:45.489Z","type":"session_meta","payload":{"id":"01a16f58","timestamp":"2026-10-24T19:17:45.139Z","cwd":"/Users/u/Projects/app/.codex-wt"}}
    {"timestamp":"2026-10-24T19:18:00.000Z","type":"response_item","payload":{}}
    """, to: root.appendingPathComponent("sessions/2026/10/24/rollout-2026-10-24T21-17-45-01a16f58.jsonl"),
             modified: Date(timeIntervalSince1970: 1_799_999_500))
    let sessions = try #require(CodexSessionReader(sessionsDirectory: root.appendingPathComponent("sessions"))
        .read(now: Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000), activityWindowSeconds: 86_400))
    #expect(sessions.map(\.id) == ["01a16f58"])
    #expect(sessions.first?.tool == "codex")
    #expect(sessions.first?.workingDirectories == [CanonicalPath("/Users/u/Projects/app/.codex-wt")!])
    #expect(sessions.first?.tempFolder == nil)
}

@Test func staleBuildObjectsCountHardLinkedFilesOnlyWhenEveryLinkIsStale() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target")
    let old = Date(timeIntervalSince1970: 1_799_990_000)   // 10 000 s before "now"
    let deps = target.appendingPathComponent("debug/deps")
    let incremental = target.appendingPathComponent("debug/incremental/app-1x2y/s-abc")
    try write(String(repeating: "a", count: 40_000), to: deps.appendingPathComponent("app-0d03.cgu1.rcgu.o"), modified: old)
    try write(String(repeating: "b", count: 40_000), to: incremental.appendingPathComponent("cgu2.o"), modified: old)
    try FileManager.default.linkItem(at: incremental.appendingPathComponent("cgu2.o"), to: deps.appendingPathComponent("app-0d03.cgu2.rcgu.o"))
    try write(String(repeating: "c", count: 40_000), to: deps.appendingPathComponent("app-0d03.rlib"), modified: old)       // not an object file
    let recent = Date(timeIntervalSince1970: 1_799_999_000)  // 1 000 s before "now": still in use
    try write(String(repeating: "d", count: 40_000), to: deps.appendingPathComponent("app-ffff.cgu1.rcgu.o"), modified: recent)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: incremental.path)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: incremental.deletingLastPathComponent().path)
    let reading = LiveStaleBuildRecords().stale(in: canonical(target), untouchedForSeconds: 3_600,
                                                now: Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000))
    guard case let .read(entries, takesUp, freesAtLeast) = reading else {
        Issue.record("expected a reading, got \(reading)")
        return
    }
    #expect(entries == 3)   // two stale .rcgu.o names plus one stale incremental folder
    #expect(takesUp.bytes >= 80_000 && takesUp.bytes < 120_000)       // two inodes, the hard link counted once
    #expect(freesAtLeast == takesUp)                                  // both links of the shared inode are stale
}

@Test func gitWorktreesAreReadFromARealRepository() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.environment = ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid", "GIT_COMMITTER_NAME": "t",
                               "GIT_COMMITTER_EMAIL": "t@example.invalid", "HOME": root.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
    }
    let repo = root.appendingPathComponent("app")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"], in: repo)
    try write("target/\nbuild/\n*.local\n", to: repo.appendingPathComponent(".gitignore"))
    try write("fn main() {}\n", to: repo.appendingPathComponent("main.rs"))
    try git(["add", "."], in: repo)
    try git(["commit", "-q", "-m", "init"], in: repo)
    try git(["worktree", "add", "-q", "-b", "feat/clean", repo.appendingPathComponent(".worktrees/clean").path], in: repo)
    try git(["worktree", "add", "-q", "-b", "feat/dirty", repo.appendingPathComponent(".worktrees/dirty").path], in: repo)
    try write("changed\n", to: repo.appendingPathComponent(".worktrees/dirty/main.rs"))
    try write("notes\n", to: repo.appendingPathComponent(".worktrees/dirty/NOTES.local"))              // ignored, not build output
    try write("obj\n", to: repo.appendingPathComponent(".worktrees/clean/target/debug/app.o"))          // ignored build output
    try write("obj\n", to: repo.appendingPathComponent(".worktrees/dirty/build/out.bin"))               // ignored build output

    let reader = LiveGitRecords()
    guard case let .worktree(clean) = reader.worktree(at: canonical(repo.appendingPathComponent(".worktrees/clean"))) else {
        Issue.record("clean worktree not read")
        return
    }
    #expect(clean.branch == "feat/clean")
    #expect(clean.mainRepository == canonical(repo))
    #expect(clean.hasChanges == false)
    #expect(clean.ignoredNonBuildPaths.isEmpty)           // target/ is build output
    #expect(clean.hasSubmodules == false && clean.isLocked == false)
    guard case let .worktree(dirty) = reader.worktree(at: canonical(repo.appendingPathComponent(".worktrees/dirty"))) else {
        Issue.record("dirty worktree not read")
        return
    }
    #expect(dirty.hasChanges == true)
    #expect(dirty.ignoredNonBuildPaths == ["NOTES.local"])
    #expect(reader.worktree(at: canonical(repo)) == .notAWorktree)                       // the main checkout is not a removable worktree
    #expect(reader.worktree(at: canonical(root)) == .notAWorktree)
    #expect(reader.isIgnored(canonical(repo.appendingPathComponent(".worktrees/dirty/build"))) == true)
    #expect(reader.isIgnored(canonical(repo.appendingPathComponent("main.rs"))) == false)
}
