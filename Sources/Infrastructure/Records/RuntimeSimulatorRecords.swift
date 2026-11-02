import Catalog
import Foundation
import SharedKernel
import os

/// Reads simulators once per instance. Later calls return that reading, including a timeout or a parse failure.
final class LiveSimulatorRecords: SimulatorRecords, Sendable {
    private let home: CanonicalPath
    private let cache = OSAllocatedUnfairLock<SimulatorReading?>(initialState: nil)

    init(home: CanonicalPath) { self.home = home }

    func read() -> SimulatorReading {
        cache.withLock { cached in
            if let cached { return cached }
            let reading = load()
            cached = reading
            return reading
        }
    }

    private func load() -> SimulatorReading {
        let base = commandEnvironment(home: home, developerDir: nil)
        guard let selected = run(
            executable: "/usr/bin/xcode-select", arguments: ["-p"], environment: base, timeout: .seconds(20), name: "xcode-select -p"
        ), selected.failure == nil else { return .notInstalled }
        let developerDir = selected.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard developerDir.hasPrefix("/") else { return .notInstalled }
        let environment = commandEnvironment(home: home, developerDir: developerDir)

        // simctl can hang when CoreSimulator is wedged, so each query dies at 20 seconds.
        guard let runtimeList = run(
            executable: "/usr/bin/xcrun", arguments: ["simctl", "runtime", "list", "--json"], environment: environment,
            timeout: .seconds(20), name: "simctl runtime list"
        ) else { return .unreadable("couldn't start simctl runtime list") }
        if let failure = runtimeList.failure { return .unreadable(failure) }
        guard let devices = run(
            executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"], environment: environment,
            timeout: .seconds(20), name: "simctl list devices"
        ) else { return .unreadable("couldn't start simctl list devices") }
        if let failure = devices.failure { return .unreadable(failure) }

        guard let runtimes = SimctlOutput.runtimes(runtimeList.output) else {
            return .unreadable("simctl runtime list output could not be read")
        }
        guard let deviceList = SimctlOutput.devices(devices.output) else {
            return .unreadable("simctl list devices output could not be read")
        }
        let assets: [SimulatorAsset]
        switch downloadAssets() {
        case .stop(let reason):
            return .unreadable(reason)
        case .found(let found):
            assets = found
        }
        return .read(SimulatorSnapshot(
            devices: deviceList, runtimes: runtimes.map(resolvingAssetFolder), downloadAssets: assets,
            stagingFolders: stagingFolders(home: home)
        ))
    }
}

private struct CommandText {
    var output: String
    var failure: String?
}

private func run(
    executable: String, arguments: [String], environment: [String: String], timeout: Duration, name: String
) -> CommandText? {
    guard let output = ToolCacheCommand.run(
        executable: executable, arguments: arguments, environment: environment, timeout: timeout
    ) else { return nil }
    if output.timedOut { return CommandText(output: output.standardOutput, failure: "\(name) timed out after 20 s") }
    if output.status != 0 { return CommandText(output: output.standardOutput, failure: failureReason(output, command: name)) }
    return CommandText(output: output.standardOutput, failure: nil)
}

private func failureReason(_ output: ToolCacheCommand.Output, command: String) -> String {
    let error = output.standardError.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !error.isEmpty { return String(error.prefix(300)) }
    return "\(command) exited with status \(output.status)"
}

private func commandEnvironment(home: CanonicalPath, developerDir: String?) -> [String: String] {
    var environment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": home.raw,
    ]
    if let developerDir { environment["DEVELOPER_DIR"] = developerDir }
    if let tmp = ProcessInfo.processInfo.environment["TMPDIR"], !tmp.isEmpty { environment["TMPDIR"] = tmp }
    return environment
}

private let simulatorAssetRoot = CanonicalPath("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime")!

private enum AssetList {
    case found([SimulatorAsset])
    case stop(String)
}

private func downloadAssets() -> AssetList {
    switch RuntimeFiles.childDirectories(simulatorAssetRoot, resolveSymlinks: true, where: { $0.lowercased().hasSuffix(".asset") }) {
    case .missing:
        return .found([])
    case .unreadable:
        return .stop("Simulator downloads couldn't be read")
    case .listed(let folders):
        return .found(folders.map { SimulatorAsset(folder: $0, version: simulatorVersion(in: $0)) })
    }
}

private func simulatorVersion(in folder: CanonicalPath) -> String? {
    guard let plist = folder.appending("Info.plist"),
          let data = try? Data(contentsOf: URL(fileURLWithPath: plist.raw)),
          let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let properties = object["MobileAssetProperties"] as? [String: Any],
          let version = properties["SimulatorVersion"] as? String else { return nil }
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Resolve the asset directory itself. Resolving the disk image first would drop a `.asset` path that is a symlink.
private func resolvingAssetFolder(_ runtime: SimulatorRuntime) -> SimulatorRuntime {
    guard let folder = runtime.assetFolder else { return runtime }
    return SimulatorRuntime(
        identifier: runtime.identifier, runtimeIdentifier: runtime.runtimeIdentifier, version: runtime.version,
        lastUsedAt: runtime.lastUsedAt, size: runtime.size, isDeletable: runtime.isDeletable,
        assetFolder: RuntimeFiles.canonical(folder.raw) ?? folder
    )
}

private func stagingFolders(home: CanonicalPath) -> [CanonicalPath] {
    var found: [CanonicalPath] = []
    if let temp = RuntimeFiles.temporaryDirectory() {
        found.append(contentsOf: deletingFolders(in: temp))
    }
    if let devices = descending(home, ["Library", "Developer", "CoreSimulator", "Devices"]) {
        found.append(contentsOf: deletingFolders(in: devices))
    }
    var seen: Set<String> = []
    return found.filter { seen.insert($0.raw).inserted }
}

private func deletingFolders(in directory: CanonicalPath) -> [CanonicalPath] {
    guard case .listed(let children) = RuntimeFiles.childDirectories(
        directory, resolveSymlinks: true, where: { $0.hasPrefix("Deleting-") }
    ) else { return [] }
    return children
}

private func descending(_ root: CanonicalPath, _ components: [String]) -> CanonicalPath? {
    var path = root
    for component in components {
        guard let next = path.appending(component) else { return nil }
        path = next
    }
    return path
}
