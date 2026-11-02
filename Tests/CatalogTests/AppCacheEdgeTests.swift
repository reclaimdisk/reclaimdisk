import Catalog
import SharedKernel
import Testing

private let now = Instant(nanosecondsSince1970: 1_800_000_000 * 1_000_000_000)

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private struct NoPlaywright: PlaywrightRecords {
    func read() -> PlaywrightReading { .notInstalled }
}

private struct Apps: AppRecords {
    let snapshot: AppSnapshot
    func read() -> AppReading { .read(snapshot) }
}

private func cache(_ name: String) -> ScannedFolder {
    ScannedFolder(path: CanonicalPath("/Users/u/Library/Caches/\(name)")!, kind: .caches, takesUp: ByteCount(400_000_000),
                  freesAtLeast: ByteCount(390_000_000), newestChange: nil, markers: [], parentMarkers: [])!
}

/// Apple's own caches are never offered, even for an installed Apple app; a bundle id owns a folder only when the name is
/// the id itself or continues it after a dot.
@Test func appCachesSkipAppleAndNeedAWholeBundleIDMatch() {
    let apps = AppSnapshot(installed: [
        InstalledApp(bundleID: "com.apple.Safari", name: "Safari"),
        InstalledApp(bundleID: "com.acme.Tool", name: "Tool"),
    ], runningBundleIDs: [])
    let folders = [cache("com.apple.Safari"), cache("com.acme.ToolBox"), cache("com.acme.Tool.ShipIt")]
    let context = RuleContext(scan: Folders(list: folders), home: CanonicalPath("/Users/u")!, now: now)
    let offered = AppRules.all(playwright: NoPlaywright(), apps: Apps(snapshot: apps)).flatMap { $0.evaluate(context).candidates }
    #expect(offered.map(\.id.rawValue) == ["app-caches:/Users/u/Library/Caches/com.acme.Tool.ShipIt"])
}
