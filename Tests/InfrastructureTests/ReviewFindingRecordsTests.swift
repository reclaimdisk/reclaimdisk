import Catalog
import Foundation
import SharedKernel
import Testing
@testable import Infrastructure

/// `git rev-parse --abbrev-ref HEAD` prints "HEAD" for a detached worktree; that is no branch.
@Test func aDetachedWorktreeHasNoBranch() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("detached-\(UUID().uuidString)").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
    try Data("x\n".utf8).write(to: repo.appendingPathComponent("file.txt"))
    try git(["add", "."], in: repo)
    try git(["commit", "-q", "-m", "init"], in: repo)
    let worktree = repo.appendingPathComponent(".worktrees/snapshot")
    try git(["worktree", "add", "-q", "--detach", worktree.path], in: repo)
    guard case .worktree(let state) = LiveGitRecords().worktree(at: CanonicalPath(worktree.path)!) else {
        Issue.record("expected a worktree reading")
        return
    }
    #expect(state.branch == nil)
}

/// In a monorepo git names the ignored folder itself, deep inside the tree; its own name decides whether it is build output.
@Test func nestedBuildOutputInAMonorepoIsBuildOutput() {
    let summary = StatusSummary.parse("!! apps/web/.svelte-kit/\n!! products/api/node_modules/\n!! backend/__pycache__/\n!! apps/web/.env.local\n",
                                      buildOutputNames: ["node_modules", ".svelte-kit", "__pycache__"])
    #expect(summary.ignoredNonBuildPaths == ["apps/web/.env.local"])
    #expect(!summary.hasChanges)
}

/// `npm cache clean --force` empties `<cache>/_cacache` and leaves `_npx` and `_logs`, so only `_cacache` is what it frees.
@Test func npmsCleanCommandEmptiesItsCacacheFolder() {
    let reported = CanonicalPath("/Users/u/.npm")!
    #expect(PackageCacheLayout.cleanedFolder(tool: "npm", reported: reported) == CanonicalPath("/Users/u/.npm/_cacache"))
    #expect(PackageCacheLayout.cleanedFolder(tool: "pip", reported: CanonicalPath("/Users/u/Library/Caches/pip")!)
        == CanonicalPath("/Users/u/Library/Caches/pip"))
}

/// A query must not change anything: no update check that writes a file or reaches the network.
@Test func packageManagerQueriesTurnOffUpdateChecks() {
    let environment = PackageCacheLayout.queryEnvironment(home: CanonicalPath("/Users/u")!, path: "/usr/bin")
    #expect(environment["npm_config_update_notifier"] == "false")
    #expect(environment["PIP_DISABLE_PIP_VERSION_CHECK"] == "1")
    #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(environment["HOME"] == "/Users/u")
}

/// `docker run postgres` records the image as "postgres"; Docker means `postgres:latest`.
@Test func aContainerNamingAnImageWithoutATagUsesItsLatestTag() throws {
    let images = #"{"ID":"aaaaaaaaaaaa","Repository":"postgres","Tag":"latest","CreatedAt":"2026-10-01 10:00:00 +0200 CEST","Size":"480MB"}"#
    let containers = #"{"Image":"postgres","Mounts":""}"#
    let parsed = try #require(DockerOutput.images(images, containers: containers))
    #expect(parsed.first?.usedByContainer == true)
}
