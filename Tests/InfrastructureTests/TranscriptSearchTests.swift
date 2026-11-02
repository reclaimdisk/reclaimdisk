import Catalog
import Foundation
import SharedKernel
import Testing
@testable import Infrastructure

/// Transcripts reach hundreds of megabytes, so working directories are found by their key rather than by decoding every
/// line. A "cwd" that is only text inside a message must not count, and escapes in a real one must be decoded.
@Test func workingDirectoriesComeFromTheCwdKeyNotFromMessageText() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("transcripts-\(UUID().uuidString)").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent(".claude-work/projects/-Users-u-Projects-app")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let file = project.appendingPathComponent("cccc.jsonl")
    try Data("""
    {"type":"user","cwd":"/Users/u/Projects/app","message":{"content":"run it in {\\"cwd\\":\\"/Users/u/elsewhere\\"}"}}
    {"parentUuid":null,"cwd":"/Users/u/Projects/caf\\u00e9 \\"one\\"","type":"assistant"}
    {"type":"summary","summary":"no working directory here"}
    {"type":"user","cwd":"/Users/u/Projects/app"}
    """.utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_799_999_000)], ofItemAtPath: file.path)
    let reader = ClaudeSessionReader(configDirectories: [root.appendingPathComponent(".claude-work")], tempRoot: CanonicalPath("/private/tmp/claude-501")!)
    let sessions = try #require(reader.read(now: Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000), activityWindowSeconds: 86_400))
    #expect(sessions.first?.workingDirectories == [
        CanonicalPath("/Users/u/Projects/app")!, CanonicalPath("/Users/u/Projects/café \"one\"")!,
    ])
}

/// A Codex rollout names its session in the first `session_meta` line; the rest of the file is never decoded.
@Test func aCodexRolloutIsIdentifiedByItsFirstSessionMetaLine() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rollouts-\(UUID().uuidString)").resolvingSymlinksInPath()
    let file = root.appendingPathComponent("sessions/2026/11/01/rollout-2026-11-01T10-00-00-0b0b.jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("""
    {"type":"event_msg","payload":{}}\r
    {"type":"session_meta","payload":{"id":"0b0b","cwd":"/Users/u/Projects/app"}}\r
    {"type":"session_meta","payload":{"id":"later","cwd":"/Users/u/other"}}
    """.utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_799_999_000)], ofItemAtPath: file.path)
    let sessions = try #require(CodexSessionReader(sessionsDirectory: root.appendingPathComponent("sessions"))
        .read(now: Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000), activityWindowSeconds: 86_400))
    #expect(sessions.map(\.id) == ["0b0b"])
    #expect(sessions.first?.workingDirectories == [CanonicalPath("/Users/u/Projects/app")!])
}
