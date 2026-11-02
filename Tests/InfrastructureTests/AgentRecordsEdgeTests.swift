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

/// SwiftPM's `.build` is build output like Cargo's `target`, so it never blocks a worktree as "ignored files".
@Test func swiftPackageBuildOutputIsNotAnIgnoredNote() throws {
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
    let repo = root.appendingPathComponent("pkg")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"], in: repo)
    try write(".build/\n", to: repo.appendingPathComponent(".gitignore"), modified: Date())
    try write("// swift-tools-version: 6.0\n", to: repo.appendingPathComponent("Package.swift"), modified: Date())
    try git(["add", "."], in: repo)
    try git(["commit", "-q", "-m", "init"], in: repo)
    let worktree = repo.appendingPathComponent(".worktrees/feat")
    try git(["worktree", "add", "-q", "-b", "feat", worktree.path], in: repo)
    try write("obj\n", to: worktree.appendingPathComponent(".build/debug/pkg.o"), modified: Date())
    guard case .worktree(let state) = LiveGitRecords().worktree(at: CanonicalPath(worktree.path)!) else {
        Issue.record("expected a worktree reading")
        return
    }
    #expect(state.ignoredNonBuildPaths.isEmpty)
    #expect(!state.hasChanges)
}

/// Reading a worktree must not run a program the repository's configuration names: `core.fsmonitor` would start one on
/// every `git status`.
@Test func readingAWorktreeNeverRunsItsFsmonitorHook() throws {
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
    try write("x\n", to: repo.appendingPathComponent("file.txt"), modified: Date())
    try git(["add", "."], in: repo)
    try git(["commit", "-q", "-m", "init"], in: repo)
    let worktree = repo.appendingPathComponent(".worktrees/feat")
    try git(["worktree", "add", "-q", "-b", "feat", worktree.path], in: repo)
    let marker = root.appendingPathComponent("hook-ran")
    let hook = root.appendingPathComponent("fsmonitor-hook")
    try write("#!/bin/sh\ntouch '\(marker.path)'\n", to: hook, modified: Date())
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    try git(["config", "core.fsmonitor", hook.path], in: repo)
    _ = LiveGitRecords().worktree(at: CanonicalPath(worktree.path)!)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}
