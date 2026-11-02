import Catalog
import Foundation
import SharedKernel
import os

/// Reads the Android SDK once per instance. It lists folders and config files; it never installs or deletes.
final class LiveAndroidRecords: AndroidRecords, Sendable {
    private let home: CanonicalPath
    private let cache = OSAllocatedUnfairLock<AndroidReading?>(initialState: nil)

    init(home: CanonicalPath) { self.home = home }

    func read() -> AndroidReading {
        cache.withLock { cached in
            if let cached { return cached }
            let reading = load()
            cached = reading
            return reading
        }
    }

    private func load() -> AndroidReading {
        guard let sdkRoot = sdkRoot(home: home) else { return .notInstalled }
        let images: [AndroidImage]
        switch systemImages(sdkRoot: sdkRoot) {
        case .unreadable(let reason):
            return .unreadable(reason)
        case .found(let found):
            images = found
        }
        let devices: [AndroidVirtualDevice]
        switch virtualDevices(home: home, sdkRoot: sdkRoot) {
        case .unreadable(let reason):
            return .unreadable(reason)
        case .found(let found):
            devices = found
        }
        return .read(AndroidSnapshot(
            sdkManager: commandTool(sdkRoot, "sdkmanager"), avdManager: commandTool(sdkRoot, "avdmanager"), images: images,
            virtualDevices: devices
        ))
    }
}

private func sdkRoot(home: CanonicalPath) -> CanonicalPath? {
    let environment = ProcessInfo.processInfo.environment
    if let chosen = nonempty(environment["ANDROID_HOME"]) {
        return existingDirectory(expand(chosen, home: home))
    }
    if let chosen = nonempty(environment["ANDROID_SDK_ROOT"]) {
        return existingDirectory(expand(chosen, home: home))
    }
    guard let fallback = home.appending("Library")?.appending("Android")?.appending("sdk") else { return nil }
    return existingDirectory(fallback.raw)
}

private func existingDirectory(_ raw: String) -> CanonicalPath? {
    guard let path = RuntimeFiles.canonical(raw), RuntimeFiles.directoryExists(path) else { return nil }
    return path
}

private func nonempty(_ text: String?) -> String? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func expand(_ text: String, home: CanonicalPath) -> String {
    if text == "~" { return home.raw }
    if text.hasPrefix("~/") { return home.raw + String(text.dropFirst()) }
    return text
}

private enum FolderRead<Value> {
    case found(Value)
    case unreadable(String)
}

private func systemImages(sdkRoot: CanonicalPath) -> FolderRead<[AndroidImage]> {
    guard let root = sdkRoot.appending("system-images") else { return .found([]) }
    switch RuntimeFiles.childDirectories(root, resolveSymlinks: false) {
    case .missing:
        return .found([])
    case .unreadable:
        return .unreadable("The Android system-images folder couldn't be read")
    case .listed(let apis):
        var images: [AndroidImage] = []
        for api in apis {
            guard case .listed(let tags) = RuntimeFiles.childDirectories(api, resolveSymlinks: false) else { continue }
            for tag in tags {
                guard case .listed(let abis) = RuntimeFiles.childDirectories(tag, resolveSymlinks: false) else { continue }
                for abi in abis where RuntimeFiles.containsFile(abi) {
                    guard let package = AndroidOutput.package(forImageFolder: abi, sdkRoot: sdkRoot) else { continue }
                    images.append(AndroidImage(package: package, folder: abi))
                }
            }
        }
        return .found(images)
    }
}

private func virtualDevices(home: CanonicalPath, sdkRoot: CanonicalPath) -> FolderRead<[AndroidVirtualDevice]> {
    guard let root = home.appending(".android")?.appending("avd") else { return .found([]) }
    switch RuntimeFiles.childDirectories(root, resolveSymlinks: false, where: { $0.hasSuffix(".avd") }) {
    case .missing:
        return .found([])
    case .unreadable:
        return .unreadable("The Android virtual-device folder couldn't be read")
    case .listed(let folders):
        var devices: [AndroidVirtualDevice] = []
        for folder in folders {
            let name = String(folder.lastComponent.dropLast(".avd".count))
            guard !name.isEmpty, let config = folder.appending("config.ini"), RuntimeFiles.fileExists(config) else { continue }
            let imageFolder = readText(config).flatMap { AndroidOutput.imageFolder(fromConfig: $0, sdkRoot: sdkRoot) }
            devices.append(AndroidVirtualDevice(name: name, folder: folder, imageFolder: imageFolder))
        }
        return .found(devices)
    }
}

private func commandTool(_ sdkRoot: CanonicalPath, _ name: String) -> CanonicalPath? {
    guard let path = sdkRoot.appending("cmdline-tools")?.appending("latest")?.appending("bin")?.appending(name),
          RuntimeFiles.fileExists(path) else { return nil }
    return path
}

private func readText(_ path: CanonicalPath) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path.raw)) else { return nil }
    return String(data: data, encoding: .utf8)
}
