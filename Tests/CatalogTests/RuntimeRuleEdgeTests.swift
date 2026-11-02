import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let twoMonthsAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 60 * 86_400) * second)
private let tenDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 10 * 86_400) * second)

private struct NoFolders: ScanQuery {
    func folders() -> [ScannedFolder] { [] }
}

private struct Simulators: SimulatorRecords {
    let snapshot: SimulatorSnapshot
    func read() -> SimulatorReading { .read(snapshot) }
}

private struct NoAndroid: AndroidRecords {
    func read() -> AndroidReading { .notInstalled }
}

private struct NoXcode: XcodeRecords {
    func workspacePath(ofDerivedData folder: CanonicalPath) -> String? { nil }
}

private func runtime(_ id: String, _ runtimeIdentifier: String, lastUsedAt: Instant?, deletable: Bool = true) -> SimulatorRuntime {
    SimulatorRuntime(identifier: id, runtimeIdentifier: runtimeIdentifier, version: "1.0", lastUsedAt: lastUsedAt,
                     size: ByteCount(1_000), isDeletable: deletable, assetFolder: nil)
}

/// Each condition on its own: a runtime an available simulator uses stays however old it is, one simctl can't delete is
/// never offered, one used in the last 30 days stays, one never used counts as old, and an unavailable simulator does
/// not keep its runtime.
@Test func anUnusedRuntimeMustBeDeletableUnusedByAvailableSimulatorsAndOld() {
    let snapshot = SimulatorSnapshot(
        devices: [
            SimulatorDevice(udid: "A1", name: "iPhone A", runtimeIdentifier: "rt.used", isAvailable: true, dataSize: nil),
            SimulatorDevice(udid: "B2", name: "iPhone B", runtimeIdentifier: "rt.broken", isAvailable: false, dataSize: nil),
        ],
        runtimes: [
            runtime("used", "rt.used", lastUsedAt: twoMonthsAgo),
            runtime("locked", "rt.locked", lastUsedAt: twoMonthsAgo, deletable: false),
            runtime("recent", "rt.recent", lastUsedAt: tenDaysAgo),
            runtime("never", "rt.never", lastUsedAt: nil),
            runtime("broken", "rt.broken", lastUsedAt: twoMonthsAgo),
        ],
        downloadAssets: [], stagingFolders: []
    )
    let rules = RuntimeRules.all(simulators: Simulators(snapshot: snapshot), android: NoAndroid(), xcode: NoXcode())
    let context = RuleContext(scan: NoFolders(), home: CanonicalPath("/Users/u")!, now: now)
    let offered = rules.flatMap { $0.evaluate(context).candidates }.filter { $0.rule.rawValue == "unused-simulator-runtimes" }
    #expect(offered.map(\.id.rawValue).sorted() == [
        "unused-simulator-runtimes:simctl/runtime/broken", "unused-simulator-runtimes:simctl/runtime/never",
    ])
}
