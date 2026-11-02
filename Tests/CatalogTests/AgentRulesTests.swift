import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let hourAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3_600) * second)
private let threeDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3 * 86_400) * second)
private let home = CanonicalPath("/Users/u")!
private let cargo: Set<String> = ["CACHEDIR.TAG", ".rustc_info.json"]
private func path(_ raw: String) -> CanonicalPath { CanonicalPath(raw)! }

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private func folder(_ raw: String, kind: Kind = .buildOutput, takes: UInt64 = 5_000, frees: UInt64 = 4_000,
                    newest: Instant? = threeDaysAgo, markers: Set<String> = [], parent: Set<String> = []) -> ScannedFolder {
    ScannedFolder(path: path(raw), kind: kind, takesUp: ByteCount(takes), freesAtLeast: ByteCount(frees),
                  newestChange: newest, markers: markers, parentMarkers: parent)!
}

private struct Sessions: SessionRecords {
    let reading: SessionReading
    func sessions() -> SessionReading { reading }
}

private struct Git: GitRecords {
    var worktrees: [CanonicalPath: WorktreeReading] = [:]
    var ignored: [CanonicalPath: Bool] = [:]
    func worktree(at path: CanonicalPath) -> WorktreeReading { worktrees[path] ?? .notAWorktree }
    func isIgnored(_ path: CanonicalPath) -> Bool? { ignored[path] }
}

private struct Processes: ProcessRecords {
    let reading: ProcessReading
    func processes() -> ProcessReading { reading }
}

private struct Stale: StaleBuildRecords {
    let readings: [CanonicalPath: StaleReading]
    func stale(in target: CanonicalPath, untouchedForSeconds: Int64, now: Instant) -> StaleReading {
        readings[target] ?? .unreadable("no fixture")
    }
}

private let endedTemp = "/private/tmp/claude-501/-Users-u-Projects-app/11111111-aaaa-bbbb-cccc-000000000001"
private let liveTemp = "/private/tmp/claude-501/-Users-u-Projects-app/22222222-aaaa-bbbb-cccc-000000000002"
private let unknownTemp = "/private/tmp/claude-501/-Users-u-Projects-web/33333333-aaaa-bbbb-cccc-000000000003"

private let sessions = SessionReading.read([
    AgentSession(tool: "claude", id: "11111111-aaaa-bbbb-cccc-000000000001", lastActivity: threeDaysAgo,
                 workingDirectories: [path("/Users/u/Projects/app/.worktrees/old")], tempFolder: path(endedTemp)),
    AgentSession(tool: "claude", id: "22222222-aaaa-bbbb-cccc-000000000002", lastActivity: hourAgo,
                 workingDirectories: [path("/Users/u/Projects/app/.worktrees/busy")], tempFolder: path(liveTemp)),
    AgentSession(tool: "codex", id: "01a16f58", lastActivity: hourAgo,
                 workingDirectories: [path("/Users/u/Projects/app/.claude/worktrees/codexing")], tempFolder: nil),
])

private func clean(_ branch: String) -> WorktreeReading {
    .worktree(WorktreeState(branch: branch, mainRepository: path("/Users/u/Projects/app"), hasChanges: false,
                            ignoredNonBuildPaths: [], hasSubmodules: false, isLocked: false))
}

private func rules(git: Git = Git(), processes: ProcessReading = .read([]), stale: [CanonicalPath: StaleReading] = [:],
                   sessionReading: SessionReading = sessions) -> [any Rule] {
    AgentRules.all(sessions: Sessions(reading: sessionReading), git: git, processes: Processes(reading: processes),
                   stale: Stale(readings: stale))
}

private func evaluate(_ rules: [any Rule], _ folders: [ScannedFolder]) -> RuleResult {
    let context = RuleContext(scan: Folders(list: folders), home: home, now: now)
    return rules.reduce(RuleResult(candidates: [], notes: [])) { sum, rule in
        let result = rule.evaluate(context)
        return RuleResult(candidates: sum.candidates + result.candidates, notes: sum.notes + result.notes)
    }
}

private func only(_ id: String, _ rules: [any Rule]) -> [any Rule] { rules.filter { $0.id.rawValue == id } }

@Test func buildOutputInEndedAgentTempFoldersIsRebuildableAndLiveOrUnknownSessionsBlockIt() {
    let result = evaluate(only("agent-temp-build-output", rules()), [
        folder("\(endedTemp)/scratchpad/target", markers: cargo),
        folder("\(endedTemp)/scratchpad/web/node_modules", parent: ["package.json"]),
        folder("\(endedTemp)/scratchpad/web/node_modules/x/node_modules", parent: ["package.json"]),   // nested
        folder("\(liveTemp)/scratchpad/target", markers: cargo),
        folder("\(unknownTemp)/scratchpad/.venv", markers: ["pyvenv.cfg"]),
        folder("\(endedTemp)/scratchpad/notes", kind: .agentSessions),                                 // not build output
    ])
    #expect(result.candidates.map(\.id.rawValue).sorted() == [
        "agent-temp-build-output:\(endedTemp)/scratchpad/target",
        "agent-temp-build-output:\(endedTemp)/scratchpad/web/node_modules",
        "agent-temp-build-output:\(liveTemp)/scratchpad/target",
        "agent-temp-build-output:\(unknownTemp)/scratchpad/.venv",
    ])
    let byPath = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.target, $0) })
    let ended = byPath[.path(path("\(endedTemp)/scratchpad/target"))]
    #expect(ended?.reclaimClass == .rebuildable)
    #expect(ended?.isPreselected == true)
    #expect(ended?.evidence.contains { $0.source == .sessionRecords } == true)
    #expect(byPath[.path(path("\(liveTemp)/scratchpad/target"))]?.blockedReason != nil)
    #expect(byPath[.path(path("\(unknownTemp)/scratchpad/.venv"))]?.blockedReason != nil)
    #expect(byPath[.path(path("\(unknownTemp)/scratchpad/.venv"))]?.isPreselected == false)
}

@Test func unreadableSessionRecordsBlockEverythingThatDependsOnThem() {
    let result = evaluate(only("agent-temp-build-output", rules(sessionReading: .unreadable("permission denied"))),
                          [folder("\(endedTemp)/scratchpad/target", markers: cargo)])
    #expect(result.candidates.count == 1)
    #expect(result.candidates.first?.blockedReason != nil)
}

@Test func endedAgentTempFoldersAreReportOnly() {
    let result = evaluate(only("agent-temp-folders", rules()), [
        folder(endedTemp, kind: .agentSessions, takes: 900_000_000, frees: 800_000_000),
        folder(liveTemp, kind: .agentSessions, takes: 900_000_000, frees: 800_000_000),
    ])
    #expect(result.candidates.map(\.id.rawValue) == ["agent-temp-folders:\(endedTemp)"])
    #expect(result.candidates.first?.reclaimClass == .reportOnly)
    #expect(result.candidates.first?.explanation != nil)
}

@Test func cleanWorktreesOfEndedSessionsAreRemovedWithGitAndOthersExplainWhyNot() {
    let git = Git(worktrees: [
        path("/Users/u/Projects/app/.worktrees/old"): clean("feat/old"),
        path("/Users/u/Projects/app/.worktrees/busy"): clean("feat/busy"),
        path("/Users/u/Projects/app/.worktrees/dirty"): .worktree(WorktreeState(
            branch: "feat/dirty", mainRepository: path("/Users/u/Projects/app"), hasChanges: true,
            ignoredNonBuildPaths: [], hasSubmodules: false, isLocked: false)),
        path("/Users/u/Projects/app/.worktrees/notes"): .worktree(WorktreeState(
            branch: "feat/notes", mainRepository: path("/Users/u/Projects/app"), hasChanges: false,
            ignoredNonBuildPaths: ["PLAN.md"], hasSubmodules: false, isLocked: false)),
        path("/Users/u/Projects/app/.claude/worktrees/codexing"): clean("feat/codexing"),
        path("/Users/u/Projects/app/.worktrees/held"): clean("feat/held"),
    ])
    let processes = ProcessReading.read([RunningProcess(name: "node", workingDirectory: path("/Users/u/Projects/app/.worktrees/held/web"))])
    let result = evaluate(only("agent-worktrees", rules(git: git, processes: processes)), [
        folder("/Users/u/Projects/app/.worktrees/old", kind: .agentSessions),
        folder("/Users/u/Projects/app/.worktrees/busy", kind: .agentSessions),
        folder("/Users/u/Projects/app/.worktrees/dirty", kind: .agentSessions),
        folder("/Users/u/Projects/app/.worktrees/notes", kind: .agentSessions),
        folder("/Users/u/Projects/app/.claude/worktrees/codexing", kind: .agentSessions),
        folder("/Users/u/Projects/app/.worktrees/held", kind: .agentSessions),
        folder("/Users/u/Projects/app/.worktrees/_target", markers: cargo),   // a shared build folder, not a worktree
    ])
    let byPath = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.target, $0) })
    #expect(byPath.count == 6)
    let old = byPath[.path(path("/Users/u/Projects/app/.worktrees/old"))]
    #expect(old?.reclaimClass == .toolManaged)
    #expect(old?.blockedReason == nil)
    #expect(old?.action == .toolCommand(ToolCommand(executable: "git", arguments: [
        "-C", "/Users/u/Projects/app", "worktree", "remove", "/Users/u/Projects/app/.worktrees/old",
    ])!))
    #expect(old?.estimate.freesAtLeast == ByteCount(4_000))
    #expect(old?.recovery?.text.contains("feat/old") == true)
    for blocked in ["busy", ".claude/worktrees/codexing", "dirty", "notes", "held"] {
        let raw = blocked.hasPrefix(".") ? "/Users/u/Projects/app/\(blocked)" : "/Users/u/Projects/app/.worktrees/\(blocked)"
        #expect(byPath[.path(path(raw))]?.blockedReason != nil, "\(blocked)")
    }
    #expect(byPath[.path(path("/Users/u/Projects/app/.worktrees/_target"))] == nil)
}

@Test func gradleBuildOutputMustBeGitIgnored() {
    let git = Git(ignored: [path("/Users/u/Projects/droid/build"): true, path("/Users/u/Projects/tracked/build"): false])
    let result = evaluate(only("gradle-build-output", rules(git: git)), [
        folder("/Users/u/Projects/droid/build", parent: ["build.gradle.kts"]),
        folder("/Users/u/Projects/tracked/build", parent: ["build.gradle"]),
        folder("/Users/u/Projects/unknown/build", parent: ["build.gradle"]),   // git can't say: not a candidate
        folder("/Users/u/Projects/plain/build", parent: []),
    ])
    #expect(result.candidates.map(\.id.rawValue) == ["gradle-build-output:/Users/u/Projects/droid/build"])
    #expect(result.candidates.first?.recovery?.text == "gradle build")
}

@Test func staleObjectsInsideABusySharedBuildFolderAreOfferedSeparately() {
    let shared = path("/Users/u/Projects/rc/.worktrees/_target")
    let stale: [CanonicalPath: StaleReading] = [shared: .read(entries: 574_067, takesUp: ByteCount(46_000_000_000), freesAtLeast: ByteCount(44_000_000_000))]
    let busyFolder = folder(shared.raw, takes: 53_000_000_000, frees: 50_000_000_000, newest: hourAgo, markers: cargo)
    let idle = evaluate(only("rust-stale-objects", rules(stale: stale)), [busyFolder])
    #expect(idle.candidates.count == 1)
    let candidate = idle.candidates.first
    #expect(candidate?.id.rawValue == "rust-stale-objects:\(shared.raw)")
    #expect(candidate?.reclaimClass == .rebuildable)
    #expect(candidate?.estimate.freesAtLeast == ByteCount(44_000_000_000))
    #expect(candidate?.action == .deleteStale(in: shared, patterns: ["debug/deps/*.rcgu.o", "debug/incremental/*"], untouchedForSeconds: 3_600))
    #expect(candidate?.blockedReason == nil)

    let compiling = ProcessReading.read([RunningProcess(name: "rustc", workingDirectory: path("/Users/u/Projects/rc/rust"))])
    let busy = evaluate(only("rust-stale-objects", rules(processes: compiling, stale: stale)), [busyFolder])
    #expect(busy.candidates.first?.blockedReason != nil)

    let quiet = evaluate(only("rust-stale-objects", rules(stale: stale)), [folder(shared.raw, newest: threeDaysAgo, markers: cargo)])
    #expect(quiet.candidates.isEmpty)   // an idle build folder is offered whole by the Rust build folder rule

    let small: [CanonicalPath: StaleReading] = [shared: .read(entries: 3, takesUp: ByteCount(10_000_000), freesAtLeast: ByteCount(10_000_000))]
    #expect(evaluate(only("rust-stale-objects", rules(stale: small)), [busyFolder]).candidates.isEmpty)   // under 256 MiB
}

@Test func everyAgentRuleHasItsId() {
    #expect(Set(rules().map(\.id.rawValue)) == [
        "agent-temp-build-output", "agent-temp-folders", "agent-worktrees", "gradle-build-output", "rust-stale-objects",
    ])
}
