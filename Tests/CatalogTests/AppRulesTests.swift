import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let threeDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3 * 86_400) * second)
private let home = CanonicalPath("/Users/u")!
private let caches = "/Users/u/Library/Caches"
private func path(_ raw: String) -> CanonicalPath { CanonicalPath(raw)! }

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private func folder(_ raw: String, takes: UInt64 = 400_000_000, frees: UInt64 = 390_000_000) -> ScannedFolder {
    ScannedFolder(path: path(raw), kind: .caches, takesUp: ByteCount(takes), freesAtLeast: ByteCount(frees),
                  newestChange: threeDaysAgo, markers: [], parentMarkers: [])!
}

private struct Playwright: PlaywrightRecords {
    let reading: PlaywrightReading
    func read() -> PlaywrightReading { reading }
}

private struct Apps: AppRecords {
    let reading: AppReading
    func read() -> AppReading { reading }
}

private let playwright = PlaywrightSnapshot(
    cacheFolder: path("\(caches)/ms-playwright"),
    builds: [
        PlaywrightBuild(browser: "chromium", revision: "1187", folder: path("\(caches)/ms-playwright/chromium-1187"), size: ByteCount(344_000_000)),
        PlaywrightBuild(browser: "chromium", revision: "1248", folder: path("\(caches)/ms-playwright/chromium-1248"), size: ByteCount(366_000_000)),
        PlaywrightBuild(browser: "chromium-headless-shell", revision: "1187", folder: path("\(caches)/ms-playwright/chromium_headless_shell-1187"), size: ByteCount(177_000_000)),
        PlaywrightBuild(browser: "webkit", revision: "2370", folder: path("\(caches)/ms-playwright/webkit-2370"), size: ByteCount(299_000_000)),
    ],
    requirements: [
        PlaywrightRequirement(installation: path("/Users/u/Projects/web/node_modules/playwright-core"), browser: "chromium", revision: "1248"),
        PlaywrightRequirement(installation: path("/Users/u/Projects/web/node_modules/playwright-core"), browser: "webkit", revision: "2370"),
    ]
)

private func rules(playwright reading: PlaywrightReading = .read(playwright), apps: AppReading) -> [any Rule] {
    AppRules.all(playwright: Playwright(reading: reading), apps: Apps(reading: apps))
}

private func evaluate(_ rules: [any Rule], _ folders: [ScannedFolder]) -> RuleResult {
    let context = RuleContext(scan: Folders(list: folders), home: home, now: now)
    return rules.reduce(RuleResult(candidates: [], notes: [])) { sum, rule in
        let result = rule.evaluate(context)
        return RuleResult(candidates: sum.candidates + result.candidates, notes: sum.notes + result.notes)
    }
}

private let noApps = AppReading.read(AppSnapshot(installed: [], runningBundleIDs: []))

@Test func playwrightBuildsNoInstallationNeedsAreRebuildableRuntimes() {
    let result = evaluate(rules(apps: noApps), [folder("\(caches)/ms-playwright/chromium-1187", takes: 344_000_000, frees: 340_000_000)])
    let builds = result.candidates.filter { $0.rule.rawValue == "playwright-browser-builds" }
    #expect(builds.map(\.id.rawValue).sorted() == [
        "playwright-browser-builds:\(caches)/ms-playwright/chromium-1187",
        "playwright-browser-builds:\(caches)/ms-playwright/chromium_headless_shell-1187",
    ])
    #expect(builds.allSatisfy { $0.isInstalledRuntime && $0.reclaimClass == .rebuildable })
    #expect(builds.allSatisfy { $0.evidence.contains { $0.source == .toolRecords("playwright") } })
    let scanned = builds.first { $0.id.rawValue.hasSuffix("chromium-1187") }
    #expect(scanned?.estimate.freesAtLeast == ByteCount(340_000_000))   // the scan's figure when the folder is in it
    let reported = builds.first { $0.id.rawValue.hasSuffix("chromium_headless_shell-1187") }
    #expect(reported?.estimate.takesUp == ByteCount(177_000_000))        // the reader's own size otherwise
}

@Test func unreadablePlaywrightRecordsProtectEveryBuild() {
    let result = evaluate(rules(playwright: .unreadable(".links/abc points nowhere readable"), apps: noApps), [])
    #expect(result.candidates.isEmpty)
    #expect(result.notes.contains { $0.status == .unknown })
    #expect(evaluate(rules(playwright: .notInstalled, apps: noApps), []).candidates.isEmpty)
}

@Test func appCachesOfInstalledAppsThatAreNotRunningAreRebuildable() {
    let apps = AppReading.read(AppSnapshot(
        installed: [
            InstalledApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            InstalledApp(bundleID: "com.figma.Desktop", name: "Figma"),
            InstalledApp(bundleID: "ms-playwright", name: "Odd App"),   // a runtime folder never counts, whatever claims it
        ],
        runningBundleIDs: ["com.figma.Desktop"]
    ))
    let result = evaluate(rules(playwright: .notInstalled, apps: apps), [
        folder("\(caches)/com.tinyspeck.slackmacgap"),
        folder("\(caches)/com.tinyspeck.slackmacgap.ShipIt"),
        folder("\(caches)/com.figma.Desktop"),
        folder("\(caches)/ms-playwright"),
        folder("\(caches)/ms-playwright-mcp"),
        folder("\(caches)/com.apple.Safari"),
        folder("\(caches)/com.unknown.notinstalled"),
    ])
    let appCaches = result.candidates.filter { $0.rule.rawValue == "app-caches" }
    #expect(appCaches.map(\.id.rawValue).sorted() == [
        "app-caches:\(caches)/com.figma.Desktop",
        "app-caches:\(caches)/com.tinyspeck.slackmacgap",
        "app-caches:\(caches)/com.tinyspeck.slackmacgap.ShipIt",
    ])
    #expect(appCaches.allSatisfy { $0.reclaimClass == .rebuildable && $0.kind == .caches })
    let figma = appCaches.first { $0.id.rawValue.hasSuffix("com.figma.Desktop") }
    #expect(figma?.blockedReason?.contains("Figma") == true)   // running: quit it first
    let slack = appCaches.first { $0.id.rawValue.hasSuffix("com.tinyspeck.slackmacgap") }
    #expect(slack?.blockedReason == nil)
    #expect(slack?.recovery?.text.contains("Slack") == true)
}

@Test func nothingUnderPlaywrightMcpIsEverACandidate() {
    let apps = AppReading.read(AppSnapshot(installed: [InstalledApp(bundleID: "ms-playwright-mcp", name: "MCP")], runningBundleIDs: []))
    let result = evaluate(rules(apps: apps), [
        folder("\(caches)/ms-playwright-mcp"),
        folder("\(caches)/ms-playwright-mcp/mcp-chrome-a91d1d4"),
    ])
    #expect(!result.candidates.contains { ($0.id.rawValue).contains("ms-playwright-mcp") })
}
