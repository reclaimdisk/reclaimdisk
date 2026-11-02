import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let yesterday = Instant(nanosecondsSince1970: (1_800_000_000 - 86_400) * second)
private let twoMonthsAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 60 * 86_400) * second)
private let threeDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 3 * 86_400) * second)
private let home = CanonicalPath("/Users/u")!
private func path(_ raw: String) -> CanonicalPath { CanonicalPath(raw)! }
private let assets = "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private func folder(_ raw: String, kind: Kind = .developerTools, takes: UInt64 = 8_000, frees: UInt64 = 7_000,
                    newest: Instant? = threeDaysAgo) -> ScannedFolder {
    ScannedFolder(path: path(raw), kind: kind, takesUp: ByteCount(takes), freesAtLeast: ByteCount(frees),
                  newestChange: newest, markers: [], parentMarkers: [])!
}

private struct Simulators: SimulatorRecords {
    let reading: SimulatorReading
    func read() -> SimulatorReading { reading }
}

private struct Android: AndroidRecords {
    let reading: AndroidReading
    func read() -> AndroidReading { reading }
}

private struct Xcode: XcodeRecords {
    func workspacePath(ofDerivedData folder: CanonicalPath) -> String? {
        folder.lastComponent.hasPrefix("App-") ? "/Users/u/Projects/App/App.xcodeproj" : nil
    }
}

private let simulators = SimulatorSnapshot(
    devices: [
        SimulatorDevice(udid: "C981716A", name: "iPhone 17", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-3", isAvailable: true, dataSize: ByteCount(6_029_025_280)),
        SimulatorDevice(udid: "DEAD0001", name: "iPhone 15", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5", isAvailable: false, dataSize: ByteCount(2_000_000_000)),
    ],
    runtimes: [
        SimulatorRuntime(identifier: "81934247-D744-4C6A-A50C-BC001F2FDDE6", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-3",
                         version: "26.3.1", lastUsedAt: yesterday, size: ByteCount(8_393_503_393), isDeletable: true,
                         assetFolder: path("\(assets)/c6f07ed8ec1586ca140801a2c7c60f478e947602.asset")),
        SimulatorRuntime(identifier: "11111111-0000-0000-0000-000000000001", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0",
                         version: "11.0", lastUsedAt: twoMonthsAgo, size: ByteCount(4_000_000_000), isDeletable: true, assetFolder: nil),
    ],
    downloadAssets: [
        SimulatorAsset(folder: path("\(assets)/c6f07ed8ec1586ca140801a2c7c60f478e947602.asset"), version: "26.3.1"),
        SimulatorAsset(folder: path("\(assets)/cc1f035290d244fca4f74d9d243fcd02d2876c27.asset"), version: "18.0"),
        SimulatorAsset(folder: path("\(assets)/fb8de9a3438213a1dda310a6ab5eac9ddf8db858.asset"), version: "18.3.1"),
    ],
    stagingFolders: [path("/private/var/folders/fc/xyz/T/Deleting-1A2B3C")]
)

private func evaluate(_ rules: [any Rule], _ folders: [ScannedFolder]) -> RuleResult {
    let context = RuleContext(scan: Folders(list: folders), home: home, now: now)
    return rules.reduce(RuleResult(candidates: [], notes: [])) { sum, rule in
        let result = rule.evaluate(context)
        return RuleResult(candidates: sum.candidates + result.candidates, notes: sum.notes + result.notes)
    }
}

private func rules(simulators reading: SimulatorReading = .read(simulators), android: AndroidReading = .notInstalled) -> [any Rule] {
    RuntimeRules.all(simulators: Simulators(reading: reading), android: Android(reading: android), xcode: Xcode())
}

private func candidates(_ rule: String, _ result: RuleResult) -> [Candidate] { result.candidates.filter { $0.rule.rawValue == rule } }

@Test func derivedDataIsRebuildableAndNamesItsWorkspaceWhenKnown() {
    let result = evaluate(rules(), [
        folder("/Users/u/Library/Developer/Xcode/DerivedData/App-abcdefghijk", kind: .buildOutput),
        folder("/Users/u/Library/Developer/Xcode/DerivedData/Other-zyxwvut", kind: .buildOutput),
        folder("/Users/u/Library/Developer/Xcode/DerivedData", kind: .buildOutput),   // the parent itself is not a candidate
    ])
    let derived = candidates("xcode-derived-data", result)
    #expect(derived.map(\.id.rawValue).sorted() == [
        "xcode-derived-data:/Users/u/Library/Developer/Xcode/DerivedData/App-abcdefghijk",
        "xcode-derived-data:/Users/u/Library/Developer/Xcode/DerivedData/Other-zyxwvut",
    ])
    #expect(derived.allSatisfy { $0.reclaimClass == .rebuildable && $0.action != nil })
    let app = derived.first { $0.id.rawValue.hasSuffix("App-abcdefghijk") }
    #expect(app?.evidence.contains { $0.fact.contains("/Users/u/Projects/App/App.xcodeproj") } == true)
}

@Test func deviceSupportKeepsTheNewestVersionPerPlatform() {
    let base = "/Users/u/Library/Developer/Xcode/iOS DeviceSupport"
    let result = evaluate(rules(), [
        folder("\(base)/17.5 (21F79)"), folder("\(base)/18.2 (22C152)"), folder("\(base)/18.10 (22X1)"),
        folder("/Users/u/Library/Developer/Xcode/watchOS DeviceSupport/11.0 (22R349)"),
    ])
    #expect(candidates("xcode-device-support", result).map(\.id.rawValue).sorted() == [
        "xcode-device-support:\(base)/17.5 (21F79)", "xcode-device-support:\(base)/18.2 (22C152)",
    ])
}

@Test func simulatorRulesCoverUnavailableDevicesUnusedRuntimesStagingAndLeftovers() {
    let result = evaluate(rules(), [
        folder("\(assets)/cc1f035290d244fca4f74d9d243fcd02d2876c27.asset", takes: 8_600_000_000, frees: 8_600_000_000),
        folder("/private/var/folders/fc/xyz/T/Deleting-1A2B3C", kind: .other, takes: 300_000_000, frees: 300_000_000),
    ])
    let unavailable = candidates("unavailable-simulators", result)
    #expect(unavailable.map(\.id.rawValue) == ["unavailable-simulators:simctl/unavailable-devices"])
    #expect(unavailable.first?.reclaimClass == .toolManaged)
    #expect(unavailable.first?.action == .toolCommand(ToolCommand(executable: "xcrun", arguments: ["simctl", "delete", "unavailable"])!))
    #expect(unavailable.first?.estimate.reported == ByteCount(2_000_000_000))

    let unused = candidates("unused-simulator-runtimes", result)   // watchOS 11: no device and not used for 60 days
    #expect(unused.map(\.id.rawValue) == ["unused-simulator-runtimes:simctl/runtime/11111111-0000-0000-0000-000000000001"])
    #expect(unused.first?.isInstalledRuntime == true)
    #expect(unused.first?.evidence.contains { $0.source == .toolRecords("simctl") } == true)
    #expect(unused.first?.action == .toolCommand(ToolCommand(executable: "xcrun", arguments: ["simctl", "runtime", "delete", "11111111-0000-0000-0000-000000000001"])!))

    let staging = candidates("simulator-staging-folders", result)
    #expect(staging.map(\.id.rawValue) == ["simulator-staging-folders:/private/var/folders/fc/xyz/T/Deleting-1A2B3C"])
    #expect(staging.first?.estimate.takesUp == ByteCount(300_000_000))

    let leftovers = candidates("simulator-download-leftovers", result)
    #expect(leftovers.map(\.id.rawValue).sorted() == [
        "simulator-download-leftovers:\(assets)/cc1f035290d244fca4f74d9d243fcd02d2876c27.asset",
        "simulator-download-leftovers:\(assets)/fb8de9a3438213a1dda310a6ab5eac9ddf8db858.asset",
    ])
    #expect(leftovers.allSatisfy { $0.reclaimClass == .reportOnly && $0.action == nil && $0.explanation != nil })
    let measured = leftovers.first { $0.id.rawValue.contains("cc1f0352") }
    #expect(measured?.estimate.takesUp == ByteCount(8_600_000_000))
    #expect(measured?.evidence.contains { $0.fact.contains("18.0") } == true)
}

@Test func missingXcodeToolsAreNotApplicableAndUnreadableOutputIsUnknown() {
    let missing = evaluate(rules(simulators: .notInstalled), [])
    #expect(missing.candidates.isEmpty)
    #expect(missing.notes.contains { $0.status == .notApplicable })
    let broken = evaluate(rules(simulators: .unreadable("simctl printed no JSON")), [])
    #expect(broken.candidates.isEmpty)
    #expect(broken.notes.contains { $0.status == .unknown })
}

@Test func androidImagesNoVirtualDeviceUsesAreToolManagedRuntimes() {
    let sdk = "/Users/u/Library/Android/sdk"
    let android = AndroidReading.read(AndroidSnapshot(
        sdkManager: path("\(sdk)/cmdline-tools/latest/bin/sdkmanager"), avdManager: path("\(sdk)/cmdline-tools/latest/bin/avdmanager"),
        images: [
            AndroidImage(package: "system-images;android-35;google_apis_playstore;arm64-v8a", folder: path("\(sdk)/system-images/android-35/google_apis_playstore/arm64-v8a")),
            AndroidImage(package: "system-images;android-37.0;google_apis;arm64-v8a", folder: path("\(sdk)/system-images/android-37.0/google_apis/arm64-v8a")),
        ],
        virtualDevices: [AndroidVirtualDevice(name: "Pixel_9", folder: path("/Users/u/.android/avd/Pixel_9.avd"),
                                              imageFolder: path("\(sdk)/system-images/android-37.0/google_apis/arm64-v8a"))]
    ))
    let result = evaluate(rules(android: android), [
        folder("\(sdk)/system-images/android-35/google_apis_playstore/arm64-v8a", takes: 9_000_000_000, frees: 9_000_000_000),
        folder("\(sdk)/system-images/android-37.0/google_apis/arm64-v8a", takes: 9_000_000_000, frees: 9_000_000_000),
        folder("/Users/u/.android/avd/Pixel_9.avd", takes: 4_000_000_000, frees: 4_000_000_000),
    ])
    let images = candidates("android-system-images", result)
    #expect(images.map(\.id.rawValue) == ["android-system-images:android/system-images;android-35;google_apis_playstore;arm64-v8a"])
    #expect(images.first?.isInstalledRuntime == true)
    #expect(images.first?.action == .toolCommand(ToolCommand(executable: "\(sdk)/cmdline-tools/latest/bin/sdkmanager",
                                                             arguments: ["--uninstall", "system-images;android-35;google_apis_playstore;arm64-v8a"])!))
    let devices = candidates("android-virtual-devices", result)
    #expect(devices.map(\.id.rawValue) == ["android-virtual-devices:android/avd/Pixel_9"])
    #expect(devices.first?.isPreselected == false)
}
