import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let hourAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3_600) * second)
private let threeDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3 * 86_400) * second)
private let home = CanonicalPath("/Users/u")!
private func path(_ raw: String) -> CanonicalPath { CanonicalPath(raw)! }

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private func folder(_ raw: String, newest: Instant? = threeDaysAgo, markers: Set<String> = [], parent: Set<String> = []) -> ScannedFolder {
    ScannedFolder(path: path(raw), kind: .buildOutput, takesUp: ByteCount(5_000), freesAtLeast: ByteCount(4_000),
                  newestChange: newest, markers: markers, parentMarkers: parent)!
}

private func context(_ folders: [ScannedFolder]) -> RuleContext {
    RuleContext(scan: Folders(list: folders), home: home, now: now)
}

private func candidates(_ rules: [any Rule], _ folders: [ScannedFolder]) -> [Candidate] {
    rules.flatMap { $0.evaluate(context(folders)).candidates }
}

private struct NoSessions: SessionRecords {
    func sessions() -> SessionReading { .read([]) }
}

private struct Git: GitRecords {
    var worktrees: [CanonicalPath: WorktreeReading] = [:]
    var ignored: [CanonicalPath: Bool] = [:]
    func worktree(at path: CanonicalPath) -> WorktreeReading { worktrees[path] ?? .notAWorktree }
    func isIgnored(_ path: CanonicalPath) -> Bool? { ignored[path] }
}

private struct NoProcesses: ProcessRecords {
    func processes() -> ProcessReading { .read([]) }
}

private struct NoStale: StaleBuildRecords {
    func stale(in target: CanonicalPath, untouchedForSeconds: Int64, now: Instant) -> StaleReading { .unreadable("none") }
}

private func agentRules(_ git: Git) -> [any Rule] {
    AgentRules.all(sessions: NoSessions(), git: git, processes: NoProcesses(), stale: NoStale())
}

/// A worktree with no branch (detached HEAD) holds commits that `git worktree remove` would leave on no branch, so the
/// recovery "the branch and its commits stay" would be false.
@Test func aWorktreeWithNoBranchIsBlocked() {
    let worktree = "/Users/u/Projects/app/.worktrees/snapshot"
    let git = Git(worktrees: [path(worktree): .worktree(WorktreeState(
        branch: nil, mainRepository: path("/Users/u/Projects/app"), hasChanges: false, ignoredNonBuildPaths: [],
        hasSubmodules: false, isLocked: false
    ))])
    let found = candidates(agentRules(git), [folder(worktree)]).filter { $0.rule.rawValue == "agent-worktrees" }
    #expect(found.count == 1)
    #expect(found.first?.blockedReason?.contains("no branch") == true)
    #expect(found.first?.recovery?.text.contains("branch and its commits stay") != true)
}

/// Dependencies inside installed software (app support folders, editor extensions, tool config folders) are what that
/// software runs on, not a project's build inputs, so the scan rules leave them alone.
@Test func dependenciesOfInstalledSoftwareAreLeftAlone() {
    let lock: Set<String> = ["package.json", "package-lock.json"]
    let folders = [
        folder("/Library/Application Support/Adobe/CEP/extensions/com.example.panel/node_modules", parent: lock),
        folder("/Users/u/Library/Application Support/Example/Extensions/fs/node_modules", parent: lock),
        folder("/Users/u/.vscode/extensions/example.tool-1.0.0/node_modules", parent: lock),
        folder("/Users/u/.config/opencode/node_modules", parent: lock),
        folder("/Users/u/Library/Application Support/ExampleApp/.venv", markers: ["pyvenv.cfg"], parent: ["uv.lock"]),
        folder("/Users/u/Projects/web/node_modules", parent: lock),
        folder("/Users/u/.codex/worktrees/a1b2/web/node_modules", parent: lock),
    ]
    #expect(candidates(ScanRules.all, folders).map(\.id.rawValue).sorted() == [
        "node-dependencies:/Users/u/.codex/worktrees/a1b2/web/node_modules",
        "node-dependencies:/Users/u/Projects/web/node_modules",
    ])
}

private struct Apps: AppRecords {
    func read() -> AppReading { .read(AppSnapshot(installed: [InstalledApp(bundleID: "com.acme.Tool", name: "Tool")], runningBundleIDs: [])) }
}

private struct Playwright: PlaywrightRecords {
    func read() -> PlaywrightReading {
        .read(PlaywrightSnapshot(cacheFolder: path("/Users/u/Library/Caches/ms-playwright"), builds: [
            PlaywrightBuild(browser: "chromium", revision: "1100", folder: path("/Users/u/Library/Caches/ms-playwright/chromium-1100"), size: nil),
        ], requirements: []))
    }
}

private struct Simulators: SimulatorRecords {
    func read() -> SimulatorReading {
        .read(SimulatorSnapshot(devices: [], runtimes: [], downloadAssets: [], stagingFolders: [path("/private/var/folders/ab/T/Deleting-1A2B")]))
    }
}

private struct NoAndroid: AndroidRecords {
    func read() -> AndroidReading { .notInstalled }
}

private struct NoXcode: XcodeRecords {
    func workspacePath(ofDerivedData folder: CanonicalPath) -> String? { nil }
}

/// Every rebuildable candidate whose folder changed in the last 24 hours stays visible but blocked.
@Test func everyRebuildableFolderChangedInTheLastDayIsBlocked() {
    let gradle = "/Users/u/Projects/android/app/build"
    let recent = [
        folder(gradle, newest: hourAgo, parent: ["build.gradle.kts"]),
        folder("/Users/u/Library/Caches/com.acme.Tool", newest: hourAgo),
        folder("/Users/u/Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)", newest: hourAgo),
        folder("/Users/u/Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A3354)", newest: threeDaysAgo),
        folder("/private/var/folders/ab/T/Deleting-1A2B", newest: hourAgo),
        folder("/Users/u/Library/Caches/ms-playwright/chromium-1100", newest: hourAgo),
    ]
    let rules = agentRules(Git(ignored: [path(gradle): true]))
        + AppRules.all(playwright: Playwright(), apps: Apps())
        + RuntimeRules.all(simulators: Simulators(), android: NoAndroid(), xcode: NoXcode())
    let found = candidates(rules, recent)
    let byRule = Dictionary(grouping: found, by: \.rule.rawValue)
    for rule in ["gradle-build-output", "app-caches", "xcode-device-support", "simulator-staging-folders", "playwright-browser-builds"] {
        #expect(byRule[rule]?.count == 1, "\(rule) listed")
        #expect(byRule[rule]?.first?.blockedReason?.contains("last 24 hours") == true, "\(rule) blocked")
    }
}
