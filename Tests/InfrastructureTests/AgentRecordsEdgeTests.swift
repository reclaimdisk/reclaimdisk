import Catalog
import Foundation
import SharedKernel
import Testing
@testable import Infrastructure

private let now = Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000)

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-edges-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private func write(_ text: String, to url: URL, modified: Date) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

/// A finished session must not keep a checkout "in use": only transcripts inside the activity window give working
/// directories.
@Test func aTranscriptOlderThanTheWindowGivesNoWorkingDirectories() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent(".claude-work/projects/-Users-u-Projects-app")
    try write(#"{"type":"user","cwd":"/Users/u/Projects/app/.worktrees/old"}"#, to: project.appendingPathComponent("bbbb.jsonl"),
              modified: Date(timeIntervalSince1970: 1_800_000_000 - 2 * 86_400))
    let reader = ClaudeSessionReader(configDirectories: [root.appendingPathComponent(".claude-work")], tempRoot: CanonicalPath("/private/tmp/claude-501")!)
    let sessions = try #require(reader.read(now: now, activityWindowSeconds: 86_400))
    #expect(sessions.map(\.id) == ["bbbb"])
    #expect(sessions.first?.workingDirectories.isEmpty == true)
}

/// Cargo hard-links incremental objects into `deps`. When the incremental copy is still in use, deleting the stale
/// `deps` name frees nothing, so that inode counts toward "takes up" but not toward "frees at least".
@Test func aStaleObjectWhoseOtherLinkIsStillInUseFreesNothing() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target")
    let old = Date(timeIntervalSince1970: 1_799_990_000)
    let recent = Date(timeIntervalSince1970: 1_799_999_000)
    let busy = target.appendingPathComponent("debug/incremental/app-busy/s-new")
    try write(String(repeating: "e", count: 40_000), to: busy.appendingPathComponent("cgu3.o"), modified: recent)
    let stale = target.appendingPathComponent("debug/deps/app-0d03.cgu3.rcgu.o")
    try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.linkItem(at: busy.appendingPathComponent("cgu3.o"), to: stale)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: stale.path)   // both names share this mtime
    try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: busy.path)
    let reading = LiveStaleBuildRecords().stale(in: CanonicalPath(target.path)!, untouchedForSeconds: 3_600, now: now)
    guard case let .read(entries, takesUp, freesAtLeast) = reading else {
        Issue.record("expected a reading, got \(reading)")
        return
    }
    #expect(entries == 1)            // the deps name; the incremental folder is busy
    #expect(takesUp.bytes >= 40_000)
    #expect(freesAtLeast == .zero)
}
