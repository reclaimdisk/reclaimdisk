import SharedKernel

/// Rules for Xcode, simulators and Android. They only turn readings and the scan into candidates.
public enum RuntimeRules {
    public static func all(
        simulators: any SimulatorRecords, android: any AndroidRecords, xcode: any XcodeRecords
    ) -> [any Rule] {
        [
            DerivedDataRule(xcode: xcode),
            DeviceSupportRule(),
            UnavailableSimulatorsRule(records: simulators),
            SimulatorStagingRule(records: simulators),
            UnusedSimulatorRuntimesRule(records: simulators),
            SimulatorDownloadLeftoversRule(records: simulators),
            AndroidSystemImagesRule(records: android),
            AndroidVirtualDevicesRule(records: android),
        ]
    }
}

private struct DerivedDataRule: Rule {
    let xcode: any XcodeRecords
    let id = RuleID("xcode-derived-data")!
    let title = "Xcode DerivedData"

    func evaluate(_ context: RuleContext) -> RuleResult {
        guard let root = descending(context.home, "Library", "Developer", "Xcode", "DerivedData") else {
            return RuleResult(candidates: [], notes: [])
        }
        let candidates = directChildren(of: root, in: context.scan.folders()).compactMap { folder -> Candidate? in
            let workspace = xcode.workspacePath(ofDerivedData: folder.path).flatMap { BlankText.isBlank($0) ? nil : $0 }
            let fact = workspace.map { "Built from \($0)" } ?? folder.name
            return MeasuredPathCandidate.make(
                rule: id, title: title, folder: folder, context: context, reclaimClass: .rebuildable, facts: [fact],
                recovery: "Xcode rebuilds it on the next build", explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}

private struct DeviceSupportRule: Rule {
    let id = RuleID("xcode-device-support")!
    let title = "Xcode device support"

    func evaluate(_ context: RuleContext) -> RuleResult {
        let groups = Dictionary(grouping: deviceSupportChildren(home: context.home, in: context.scan.folders())) {
            pathKey($0.path.parent ?? $0.path)
        }
        var candidates: [Candidate] = []
        for group in groups.values {
            let versioned = group.compactMap { folder -> (ScannedFolder, [Int])? in
                guard let version = leadingVersion(folder.name) else { return nil }
                return (folder, version)
            }
            guard let newest = versioned.map(\.1).max(by: { isOlderVersion($0, than: $1) }) else { continue }
            for (folder, version) in versioned where isOlderVersion(version, than: newest) {
                guard let candidate = pathCandidate(
                    rule: id, title: title, folder: folder, context: context,
                    fact: "\(folder.name) is older than the newest device support for this platform.",
                    recovery: "Re-created when a device with that version connects"
                ) else { continue }
                candidates.append(candidate)
            }
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}

private struct UnavailableSimulatorsRule: Rule {
    let records: any SimulatorRecords
    let id = RuleID("unavailable-simulators")!
    let title = "Unavailable simulators"

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch openSimulators(records, rule: id) {
        case .stop(let result):
            return result
        case .ready(let snapshot):
            let unavailable = snapshot.devices.filter { !$0.isAvailable }
            guard !unavailable.isEmpty,
                  let command = ToolCommand(executable: "xcrun", arguments: ["simctl", "delete", "unavailable"]) else {
                return RuleResult(candidates: [], notes: [])
            }
            let knownSizes = unavailable.compactMap(\.dataSize)
            let estimate: Estimate
            if knownSizes.isEmpty {
                estimate = .unknown
            } else if let reported = try? Estimate.toolReported(tool: "simctl", size: sum(knownSizes)) {
                estimate = reported
            } else {
                return RuleResult(candidates: [], notes: [])
            }
            let names = unavailable.map(\.name).filter { !BlankText.isBlank($0) }
            let fact = names.isEmpty
                ? "Some simulators are unavailable and can't run any more."
                : "\(names.joined(separator: ", ")) can't run any more."
            guard let candidate = toolCandidate(
                rule: id, title: title, context: context, estimate: estimate, fact: fact, source: .toolRecords("simctl"),
                recovery: "Nothing to restore: these simulators can't run any more", action: .toolCommand(command),
                tool: "simctl", identifier: "unavailable-devices", isInstalledRuntime: false, blockedReason: nil,
                newestChange: nil
            ) else { return RuleResult(candidates: [], notes: []) }
            return RuleResult(candidates: [candidate], notes: [])
        }
    }
}

private struct SimulatorStagingRule: Rule {
    let records: any SimulatorRecords
    let id = RuleID("simulator-staging-folders")!
    let title = "Leftover simulator deletion folder"

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch openSimulators(records, rule: id) {
        case .stop(let result):
            return result
        case .ready(let snapshot):
            let folders = context.scan.folders()
            let candidates = snapshot.stagingFolders.compactMap { staging -> Candidate? in
                guard let folder = folders.first(where: { sameFolder($0.path, staging) }) else { return nil }
                return pathCandidate(
                    rule: id, title: title, folder: folder, context: context,
                    fact: "This folder is what's left of a deleted simulator.",
                    recovery: "Nothing to restore: it's what's left of a deleted simulator"
                )
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }
}

private struct UnusedSimulatorRuntimesRule: Rule {
    let records: any SimulatorRecords
    let id = RuleID("unused-simulator-runtimes")!
    let title = "Unused simulator runtime"

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch openSimulators(records, rule: id) {
        case .stop(let result):
            return result
        case .ready(let snapshot):
            let used = Set(snapshot.devices.filter(\.isAvailable).map(\.runtimeIdentifier))
            let candidates = snapshot.runtimes.compactMap { runtime -> Candidate? in
                guard runtime.isDeletable else { return nil }
                if let identifier = runtime.runtimeIdentifier, used.contains(identifier) { return nil }
                guard isAtLeastThirtyDaysBefore(runtime.lastUsedAt, now: context.now) else { return nil }
                guard let command = ToolCommand(
                    executable: "xcrun", arguments: ["simctl", "runtime", "delete", runtime.identifier]
                ) else { return nil }
                let estimate: Estimate
                if let size = runtime.size, let reported = try? Estimate.toolReported(tool: "simctl", size: size) {
                    estimate = reported
                } else if runtime.size == nil {
                    estimate = .unknown
                } else {
                    return nil
                }
                let name = runtime.version.isEmpty ? runtime.identifier : runtime.version
                return toolCandidate(
                    rule: id, title: title, context: context, estimate: estimate,
                    fact: "Simulator runtime \(name) is not used by an available simulator.",
                    source: .toolRecords("simctl"),
                    recovery: "Download it again in Xcode › Settings › Components", action: .toolCommand(command),
                    tool: "simctl", identifier: "runtime/\(runtime.identifier)", isInstalledRuntime: true,
                    blockedReason: nil, newestChange: runtime.lastUsedAt
                )
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }
}

private struct SimulatorDownloadLeftoversRule: Rule {
    let records: any SimulatorRecords
    let id = RuleID("simulator-download-leftovers")!
    let title = "Simulator download no runtime uses"

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch openSimulators(records, rule: id) {
        case .stop(let result):
            return result
        case .ready(let snapshot):
            let used = Set(snapshot.runtimes.compactMap { $0.assetFolder.map(pathKey) })
            let folders = context.scan.folders()
            let candidates = snapshot.downloadAssets.compactMap { asset -> Candidate? in
                guard !used.contains(pathKey(asset.folder)) else { return nil }
                let version = asset.version.flatMap { BlankText.isBlank($0) ? nil : $0 }
                let fact = version.map { "No simulator runtime uses this \($0) download" }
                    ?? "No simulator runtime uses this download"
                let scanned = folders.first { sameFolder($0.path, asset.folder) }
                let estimate: Estimate
                if let scanned, let measured = try? Estimate.measured(freesAtLeast: scanned.freesAtLeast, takesUp: scanned.takesUp) {
                    estimate = measured
                } else if scanned == nil {
                    estimate = .unknown
                } else {
                    return nil
                }
                return reportCandidate(
                    rule: id, title: title, context: context, path: asset.folder, estimate: estimate, fact: fact,
                    source: .toolRecords("simctl"), newestChange: scanned?.newestChange,
                    explanation: "There's no documented way to remove a simulator download that no runtime uses. Reveal it in Finder; removing it needs an administrator password."
                )
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }
}

private struct AndroidSystemImagesRule: Rule {
    let records: any AndroidRecords
    let id = RuleID("android-system-images")!
    let title = "Unused Android system image"

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch openAndroid(records, rule: id) {
        case .stop(let result):
            return result
        case .ready(let snapshot):
            let used = Set(snapshot.virtualDevices.compactMap { $0.imageFolder.map(pathKey) })
            let folders = context.scan.folders()
            let blocked = snapshot.sdkManager == nil ? "The Android command-line tools (sdkmanager) aren't installed" : nil
            let executable = snapshot.sdkManager?.raw ?? "sdkmanager"
            let candidates = snapshot.images.compactMap { image -> Candidate? in
                guard !used.contains(pathKey(image.folder)),
                      let folder = folders.first(where: { sameFolder($0.path, image.folder) }),
                      let estimate = try? Estimate.measured(freesAtLeast: folder.freesAtLeast, takesUp: folder.takesUp),
                      let command = ToolCommand(executable: executable, arguments: ["--uninstall", image.package]) else { return nil }
                return toolCandidate(
                    rule: id, title: title, context: context, estimate: estimate,
                    fact: "No virtual device uses \(image.package).", source: .toolRecords("sdkmanager"),
                    recovery: "Install it again with sdkmanager or Android Studio", action: .toolCommand(command),
                    tool: "android", identifier: image.package, isInstalledRuntime: true, blockedReason: blocked,
                    newestChange: folder.newestChange
                )
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }
}

private struct AndroidVirtualDevicesRule: Rule {
    let records: any AndroidRecords
    let id = RuleID("android-virtual-devices")!
    let title = "Android virtual device"

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch openAndroid(records, rule: id) {
        case .stop(let result):
            return result
        case .ready(let snapshot):
            let folders = context.scan.folders()
            let blocked = snapshot.avdManager == nil ? "The Android command-line tools (avdmanager) aren't installed" : nil
            let executable = snapshot.avdManager?.raw ?? "avdmanager"
            let candidates = snapshot.virtualDevices.compactMap { device -> Candidate? in
                guard let folder = folders.first(where: { sameFolder($0.path, device.folder) }),
                      let estimate = try? Estimate.measured(freesAtLeast: folder.freesAtLeast, takesUp: folder.takesUp),
                      let command = ToolCommand(executable: executable, arguments: ["delete", "avd", "-n", device.name])
                else { return nil }
                return toolCandidate(
                    rule: id, title: title, context: context, estimate: estimate,
                    fact: "Android virtual device \(device.name).", source: .toolRecords("avdmanager"),
                    recovery: "Create it again in Android Studio", action: .toolCommand(command), tool: "android",
                    identifier: "avd/\(device.name)", isInstalledRuntime: false, blockedReason: blocked,
                    newestChange: folder.newestChange
                )
            }
            return RuleResult(candidates: candidates, notes: [])
        }
    }
}

private enum Opened<Snapshot> {
    case ready(Snapshot)
    case stop(RuleResult)
}

private func openSimulators(_ records: any SimulatorRecords, rule: RuleID) -> Opened<SimulatorSnapshot> {
    switch records.read() {
    case .notInstalled:
        return .stop(noted(rule, .notApplicable, "Xcode's simulator tools aren't installed"))
    case .unreadable(let reason):
        return .stop(noted(rule, .unknown, reason))
    case .read(let snapshot):
        return .ready(snapshot)
    }
}

private func openAndroid(_ records: any AndroidRecords, rule: RuleID) -> Opened<AndroidSnapshot> {
    switch records.read() {
    case .notInstalled:
        return .stop(noted(rule, .notApplicable, "The Android SDK isn't installed"))
    case .unreadable(let reason):
        return .stop(noted(rule, .unknown, reason))
    case .read(let snapshot):
        return .ready(snapshot)
    }
}

private func noted(_ rule: RuleID, _ status: RuleNote.Status, _ reason: String) -> RuleResult {
    RuleResult(candidates: [], notes: [RuleNote(rule: rule, status: status, reason: reason)])
}

private func pathCandidate(
    rule: RuleID, title: String, folder: ScannedFolder, context: RuleContext, fact: String, recovery: String
) -> Candidate? {
    guard let estimate = try? Estimate.measured(freesAtLeast: folder.freesAtLeast, takesUp: folder.takesUp),
          let evidence = Evidence(fact: fact, source: .scan, observedAt: context.now) else { return nil }
    return try? Candidate(
        rule: rule, title: title, kind: .developerTools, target: .path(folder.path), reclaimClass: .rebuildable,
        estimate: estimate, evidence: [evidence], recovery: Recovery(recovery), action: .deletePath(folder.path),
        newestChange: folder.newestChange, isInstalledRuntime: false, blockedReason: nil, explanation: nil
    )
}

private func toolCandidate(
    rule: RuleID, title: String, context: RuleContext, estimate: Estimate, fact: String, source: EvidenceSource,
    recovery: String, action: CandidateAction, tool: String, identifier: String, isInstalledRuntime: Bool,
    blockedReason: String?, newestChange: Instant?
) -> Candidate? {
    guard let evidence = Evidence(fact: fact, source: source, observedAt: context.now) else { return nil }
    return try? Candidate(
        rule: rule, title: title, kind: .developerTools, target: .toolResource(tool: tool, identifier: identifier),
        reclaimClass: .toolManaged, estimate: estimate, evidence: [evidence], recovery: Recovery(recovery),
        action: action, newestChange: newestChange, isInstalledRuntime: isInstalledRuntime, blockedReason: blockedReason,
        explanation: nil
    )
}

private func reportCandidate(
    rule: RuleID, title: String, context: RuleContext, path: CanonicalPath, estimate: Estimate, fact: String,
    source: EvidenceSource, newestChange: Instant?, explanation: String
) -> Candidate? {
    guard let evidence = Evidence(fact: fact, source: source, observedAt: context.now) else { return nil }
    return try? Candidate(
        rule: rule, title: title, kind: .developerTools, target: .path(path), reclaimClass: .reportOnly,
        estimate: estimate, evidence: [evidence], recovery: nil, action: nil, newestChange: newestChange,
        isInstalledRuntime: false, blockedReason: nil, explanation: explanation
    )
}

/// Nil last use counts as unused. A moment in the future does not.
private func isAtLeastThirtyDaysBefore(_ lastUsedAt: Instant?, now: Instant) -> Bool {
    guard let lastUsedAt else { return true }
    let window: Int64 = 30 * 86_400 * 1_000_000_000
    let (age, overflowed) = now.nanosecondsSince1970.subtractingReportingOverflow(lastUsedAt.nanosecondsSince1970)
    if overflowed { return lastUsedAt < now }
    return age >= window
}

private func sum(_ sizes: [ByteCount]) -> ByteCount {
    var total: UInt64 = 0
    for size in sizes {
        let (next, overflowed) = total.addingReportingOverflow(size.bytes)
        if overflowed { return ByteCount(UInt64.max) }
        total = next
    }
    return ByteCount(total)
}

/// The leading dotted number, such as 18.10 from "18.10 (22X1)". Parts compare as integers, so 18.10 is newer than 18.2.
private func leadingVersion(_ name: String) -> [Int]? {
    var parts: [Int] = []
    var number = 0
    var inNumber = false
    for character in name {
        if let digit = character.wholeNumberValue {
            let (scaled, overflowed) = number.multipliedReportingOverflow(by: 10)
            if overflowed { return nil }
            let (summed, sumOverflowed) = scaled.addingReportingOverflow(digit)
            if sumOverflowed { return nil }
            number = summed
            inNumber = true
        } else if character == "." {
            guard inNumber else { return nil }
            parts.append(number)
            number = 0
            inNumber = false
        } else {
            break
        }
    }
    guard inNumber else { return nil }
    parts.append(number)
    return parts
}

private func isOlderVersion(_ version: [Int], than other: [Int]) -> Bool {
    let count = max(version.count, other.count)
    for index in 0..<count {
        let left = index < version.count ? version[index] : 0
        let right = index < other.count ? other[index] : 0
        if left != right { return left < right }
    }
    return false
}

private func deviceSupportChildren(home: CanonicalPath, in folders: [ScannedFolder]) -> [ScannedFolder] {
    guard let xcode = descending(home, "Library", "Developer", "Xcode") else { return [] }
    let xcodeKey = pathKey(xcode)
    return folders.filter { folder in
        guard let platform = folder.path.parent, let parent = platform.parent else { return false }
        let name = platform.lastComponent
        guard name.lowercased().hasSuffix(" devicesupport"), name.count > " devicesupport".count else { return false }
        return pathKey(parent) == xcodeKey
    }
}

private func directChildren(of parent: CanonicalPath, in folders: [ScannedFolder]) -> [ScannedFolder] {
    let key = pathKey(parent)
    return folders.filter { folder in
        guard let actual = folder.path.parent else { return false }
        return pathKey(actual) == key
    }
}

private func descending(_ root: CanonicalPath, _ components: String...) -> CanonicalPath? {
    var path = root
    for component in components {
        guard let next = path.appending(component) else { return nil }
        path = next
    }
    return path
}

/// `/System/Volumes/Data/Users` and `/Users` are the same folders. The scan of the Data volume records the first form.
private func sameFolder(_ scanned: CanonicalPath, _ reported: CanonicalPath) -> Bool {
    pathKey(scanned) == pathKey(reported)
}

private func pathKey(_ path: CanonicalPath) -> String {
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
