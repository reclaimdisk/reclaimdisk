import SharedKernel

/// Playwright's downloaded browsers, and cache folders that belong to an installed app.
public enum AppRules {
    public static func all(playwright: any PlaywrightRecords, apps: any AppRecords) -> [any Rule] {
        [PlaywrightBrowserBuildsRule(records: playwright), AppCachesRule(records: apps)]
    }
}

/// A browser build no live installation's `browsers.json` names. Others stay, including every override revision.
private struct PlaywrightBrowserBuildsRule: Rule {
    let id = RuleID("playwright-browser-builds")!
    let title = "Playwright browser build"
    let records: any PlaywrightRecords

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch records.read() {
        case .notInstalled:
            return RuleResult(candidates: [], notes: [])
        case .unreadable(let reason):
            return RuleResult(candidates: [], notes: [unknown(id, reason)])
        case .read(let snapshot):
            let folders = scanFolders(in: context)
            let checked = Set(snapshot.requirements.map(\.installation)).count
            let candidates = snapshot.builds.compactMap { build -> Candidate? in
                guard !isNeeded(build, snapshot.requirements) else { return nil }
                guard !isPlaywrightProfileCache(build.folder, home: context.home) else { return nil }
                return candidate(build, checked: checked, folders: folders, context: context)
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }

    private func candidate(
        _ build: PlaywrightBuild, checked: Int, folders: [String: ScannedFolder], context: RuleContext
    ) -> Candidate? {
        let scanned = folders[folderKey(build.folder)]
        let estimate: Estimate
        if let scanned, let measured = try? Estimate.measured(freesAtLeast: scanned.freesAtLeast, takesUp: scanned.takesUp) {
            estimate = measured
        } else if let size = build.size, let measured = try? Estimate.measured(freesAtLeast: size, takesUp: size) {
            estimate = measured
        } else {
            estimate = .unknown
        }
        let fact = "No Playwright installation on this Mac needs \(build.browser) \(build.revision) (checked \(checked))"
        guard let evidence = Evidence(fact: fact, source: .toolRecords("playwright"), observedAt: context.now),
              let recovery = Recovery("npx playwright install in the project that needs it") else { return nil }
        return try? Candidate(
            rule: id, title: title, kind: .caches, target: .path(build.folder), reclaimClass: .rebuildable,
            estimate: estimate, evidence: [evidence], recovery: recovery, action: .deletePath(build.folder),
            newestChange: scanned?.newestChange, isInstalledRuntime: true, blockedReason: nil, explanation: nil
        )
    }

    /// Same browser and revision, compared without case. A requirement names the build.
    private func isNeeded(_ build: PlaywrightBuild, _ requirements: [PlaywrightRequirement]) -> Bool {
        let browser = build.browser.lowercased()
        return requirements.contains { $0.revision == build.revision && $0.browser.lowercased() == browser }
    }
}

/// A cache folder directly inside `~/Library/Caches` that belongs to an installed app.
///
/// `ms-playwright-mcp` is never one of them: it holds browser profiles with sign-ins. The same fixed list leaves
/// other installed runtimes alone, whatever app claims the folder name.
private struct AppCachesRule: Rule {
    let id = RuleID("app-caches")!
    let title = "App cache"
    let records: any AppRecords

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch records.read() {
        case .unreadable(let reason):
            return RuleResult(candidates: [], notes: [unknown(id, reason)])
        case .read(let snapshot):
            let running = Set(snapshot.runningBundleIDs.map { $0.lowercased() })
            let candidates = context.scan.folders().compactMap { folder -> Candidate? in
                guard let name = directCacheFolderName(folder.path, home: context.home) else { return nil }
                guard !isPlaywrightProfileCache(folder.path, home: context.home) else { return nil }
                guard !name.hasPrefix("com.apple."), !runtimeCacheNames.contains(name) else { return nil }
                guard let app = owner(of: name, in: snapshot.installed) else { return nil }
                return candidate(folder, app: app, running: running, context: context)
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }

    private func candidate(
        _ folder: ScannedFolder, app: InstalledApp, running: Set<String>, context: RuleContext
    ) -> Candidate? {
        guard let estimate = try? Estimate.measured(freesAtLeast: folder.freesAtLeast, takesUp: folder.takesUp),
              let evidence = Evidence(
                  fact: "Belongs to \(app.name) (\(app.bundleID))", source: .fileSystem, observedAt: context.now
              ),
              let recovery = Recovery("\(app.name) fills it again as needed") else { return nil }
        let blocked = running.contains(app.bundleID.lowercased()) ? "\(app.name) is running. Quit it first." : nil
        return try? Candidate(
            rule: id, title: title, kind: .caches, target: .path(folder.path), reclaimClass: .rebuildable,
            estimate: estimate, evidence: [evidence], recovery: recovery, action: .deletePath(folder.path),
            newestChange: folder.newestChange, isInstalledRuntime: false, blockedReason: blocked, explanation: nil
        )
    }

    /// The longest bundle id wins, so `com.figma.Desktop.ShipIt` belongs to Desktop rather than a shorter prefix.
    private func owner(of name: String, in apps: [InstalledApp]) -> InstalledApp? {
        var best: InstalledApp?
        var bestID = ""
        for app in apps {
            let id = app.bundleID.lowercased()
            guard !id.isEmpty, name == id || name.hasPrefix(id + ".") else { continue }
            if best == nil || id.count > bestID.count || (id.count == bestID.count && id < bestID) {
                best = app
                bestID = id
            }
        }
        return best
    }
}

/// Names that are installed runtimes, not an app's cache. Compared without case.
private let runtimeCacheNames: Set<String> = [
    "ms-playwright", "ms-playwright-mcp", "homebrew", "pip", "pnpm", "yarn",
    "go-build", "node-gyp", "cypress", "jetbrains",
]

private func unknown(_ rule: RuleID, _ reason: String) -> RuleNote {
    let shown = BlankText.isBlank(reason) ? "The records could not be read." : reason
    return RuleNote(rule: rule, status: .unknown, reason: shown)
}

private func scanFolders(in context: RuleContext) -> [String: ScannedFolder] {
    var byKey: [String: ScannedFolder] = [:]
    for folder in context.scan.folders() where byKey[folderKey(folder.path)] == nil {
        byKey[folderKey(folder.path)] = folder
    }
    return byKey
}

/// `~/Library/Caches/ms-playwright-mcp` and everything inside it. Profiles there keep sign-ins.
private func isPlaywrightProfileCache(_ path: CanonicalPath, home: CanonicalPath) -> Bool {
    guard let root = home.appending("Library")?.appending("Caches")?.appending("ms-playwright-mcp") else { return false }
    let key = folderKey(path)
    let profiles = folderKey(root)
    return key == profiles || key.hasPrefix(profiles + "/")
}

/// The lowercased folder name when `path` is directly inside `~/Library/Caches`.
private func directCacheFolderName(_ path: CanonicalPath, home: CanonicalPath) -> String? {
    guard let caches = home.appending("Library")?.appending("Caches") else { return nil }
    let prefix = folderKey(caches) + "/"
    let key = folderKey(path)
    guard key.hasPrefix(prefix) else { return nil }
    let name = key.dropFirst(prefix.count)
    guard !name.isEmpty, !name.contains("/") else { return nil }
    return String(name)
}

/// `/System/Volumes/Data/Users` and `/Users` are the same folders. The scan records the first form.
private func folderKey(_ path: CanonicalPath) -> String {
    let dataVolume = "/System/Volumes/Data"
    let stripped: String
    if path.raw == dataVolume {
        stripped = "/"
    } else if path.raw.hasPrefix(dataVolume + "/") {
        stripped = String(path.raw.dropFirst(dataVolume.count))
    } else {
        stripped = path.raw
    }
    return stripped.lowercased()
}
