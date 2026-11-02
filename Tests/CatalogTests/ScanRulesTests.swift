import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let hourAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3_600) * second)
private let twoDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 172_800) * second)
private let home = CanonicalPath("/Users/u")!
private let cargo: Set<String> = ["CACHEDIR.TAG", ".rustc_info.json"]

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private func folder(
    _ path: String, kind: Kind = .buildOutput, takes: UInt64 = 1_000, frees: UInt64 = 900, newest: Instant? = twoDaysAgo,
    markers: Set<String> = [], parent: Set<String> = []
) -> ScannedFolder {
    ScannedFolder(
        path: CanonicalPath(path)!, kind: kind, takesUp: ByteCount(takes), freesAtLeast: ByteCount(frees),
        newestChange: newest, markers: markers, parentMarkers: parent
    )!
}

private func run(_ rule: any Rule, _ folders: [ScannedFolder]) -> RuleResult {
    rule.evaluate(RuleContext(scan: Folders(list: folders), home: home, now: now))
}

private func target(_ path: String) -> Target { .path(CanonicalPath(path)!) }

@Test func aScannedFolderNeverFreesMoreThanItTakesUp() {
    #expect(ScannedFolder(path: CanonicalPath("/a")!, kind: .other, takesUp: ByteCount(1), freesAtLeast: ByteCount(2),
                          newestChange: nil, markers: [], parentMarkers: []) == nil)
}

@Test func rustBuildFoldersAreFoundByTheirMarkersWhateverTheirName() {
    let result = run(ScanRules.rustBuildFolder, [
        folder("/Users/u/Projects/app/target", markers: cargo, parent: ["Cargo.toml"]),
        folder("/Users/u/Projects/app/.worktrees/_target", markers: cargo),
        folder("/Users/u/Projects/app/.worktrees/_target/coord", markers: cargo),                  // inside another build folder
        folder("/Users/u/Projects/app/notes", kind: .projectSource, markers: ["CACHEDIR.TAG"]),    // one marker is not enough
    ])
    #expect(result.candidates.map(\.id.rawValue).sorted() == [
        "rust-build-folder:/Users/u/Projects/app/.worktrees/_target",
        "rust-build-folder:/Users/u/Projects/app/target",
    ])
    let app = result.candidates.first { $0.target == target("/Users/u/Projects/app/target") }
    #expect(app?.reclaimClass == .rebuildable)
    #expect(app?.kind == .buildOutput)
    #expect(app?.estimate.freesAtLeast == ByteCount(900))
    #expect(app?.estimate.takesUp == ByteCount(1_000))
    #expect(app?.action == .deletePath(CanonicalPath("/Users/u/Projects/app/target")!))
    #expect(app?.recovery?.text == "cargo build")
    #expect(app?.isPreselected == true)
}

@Test func aRecentlyChangedBuildFolderStaysVisibleButBlocked() {
    let result = run(ScanRules.rustBuildFolder, [folder("/Users/u/Projects/app/target", newest: hourAgo, markers: cargo)])
    #expect(result.candidates.count == 1)
    #expect(result.candidates.first?.blockedReason != nil)
    #expect(result.candidates.first?.isPreselected == false)
}

@Test func scanRulesLeaveAgentTempFoldersAndPersonalFoldersAlone() {
    for rule in ScanRules.all {
        let result = run(rule, [
            folder("/private/tmp/claude-501/-Users-u-Projects-app/0b5e1c2d/scratchpad/target", markers: cargo),
            folder("/private/tmp/claude-501/-Users-u-Projects-web/7f00aa11/scratchpad/node_modules", parent: ["package.json", "package-lock.json"]),
            folder("/Users/u/Documents/thesis/target", markers: cargo),
            folder("/Users/u/documents/site/node_modules", parent: ["package.json", "package-lock.json"]),   // case variant
            folder("/Users/u/Desktop/demo/.next", parent: ["package.json"]),
            folder("/Users/u/Library/Mobile Documents/com~apple~CloudDocs/app/.venv", markers: ["pyvenv.cfg"], parent: ["uv.lock"]),
        ])
        #expect(result.candidates.isEmpty, "\(rule.id.rawValue)")
    }
}

@Test func nodeDependenciesNeedPackageJsonAndALockfileToBeRebuildable() {
    let result = run(ScanRules.nodeDependencies, [
        folder("/Users/u/Projects/web/node_modules", parent: ["package.json", "pnpm-lock.yaml"]),
        folder("/Users/u/Projects/api/node_modules", parent: ["package.json", "package-lock.json"]),
        folder("/Users/u/Projects/loose/node_modules", parent: ["package.json"]),
        folder("/Users/u/Projects/web/node_modules/left-pad/node_modules", parent: ["package.json", "package-lock.json"]),
        folder("/Users/u/Projects/stray/node_modules", parent: []),
    ])
    #expect(result.candidates.count == 3)
    let web = result.candidates.first { $0.target == target("/Users/u/Projects/web/node_modules") }
    #expect(web?.reclaimClass == .rebuildable)
    #expect(web?.recovery?.text == "pnpm install")
    let api = result.candidates.first { $0.target == target("/Users/u/Projects/api/node_modules") }
    #expect(api?.recovery?.text == "npm ci")
    let loose = result.candidates.first { $0.target == target("/Users/u/Projects/loose/node_modules") }
    #expect(loose?.reclaimClass == .reportOnly)
    #expect(loose?.action == nil)
    #expect(loose?.explanation != nil)
}

@Test func javaScriptBuildCachesSitBesidePackageJson() {
    let result = run(ScanRules.javaScriptBuildCaches, [
        folder("/Users/u/Projects/web/.next", parent: ["package.json"]),
        folder("/Users/u/Projects/web/.svelte-kit", parent: ["package.json"]),
        folder("/Users/u/Projects/other/.turbo", parent: []),
        folder("/Users/u/Projects/web/src", kind: .projectSource, parent: ["package.json"]),
    ])
    #expect(result.candidates.map(\.id.rawValue).sorted() == [
        "js-build-cache:/Users/u/Projects/web/.next", "js-build-cache:/Users/u/Projects/web/.svelte-kit",
    ])
    #expect(result.candidates.allSatisfy { $0.reclaimClass == .rebuildable && $0.action != nil })
}

@Test func pythonEnvironmentsAreRebuildableOnlyWithALockOrRequirementsFile() {
    let result = run(ScanRules.pythonEnvironment, [
        folder("/Users/u/Projects/api/.venv", markers: ["pyvenv.cfg"], parent: ["uv.lock"]),
        folder("/Users/u/Projects/old/venv", markers: ["pyvenv.cfg"], parent: ["requirements.txt"]),
        folder("/Users/u/Projects/adhoc/.venv", markers: ["pyvenv.cfg"], parent: []),
        folder("/Users/u/Projects/notvenv/.venv", markers: [], parent: ["uv.lock"]),
    ])
    #expect(result.candidates.count == 3)
    let api = result.candidates.first { $0.target == target("/Users/u/Projects/api/.venv") }
    #expect(api?.recovery?.text == "uv sync")
    let old = result.candidates.first { $0.target == target("/Users/u/Projects/old/venv") }
    #expect(old?.recovery?.text == "pip install -r requirements.txt")
    let adhoc = result.candidates.first { $0.target == target("/Users/u/Projects/adhoc/.venv") }
    #expect(adhoc?.reclaimClass == .reportOnly)
}

@Test func everyScanRuleHasADistinctId() {
    let ids = ScanRules.all.map(\.id.rawValue)
    #expect(Set(ids).count == ids.count)
    #expect(Set(ids) == ["rust-build-folder", "node-dependencies", "js-build-cache", "python-environment"])
}
