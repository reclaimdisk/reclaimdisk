import SharedKernel

/// A read-only look at Xcode simulators. Implementations may run query commands; they never delete a simulator.
public protocol SimulatorRecords: Sendable {
    func read() -> SimulatorReading
}

/// A read-only look at the Android SDK and its virtual devices.
public protocol AndroidRecords: Sendable {
    func read() -> AndroidReading
}

/// Where a DerivedData folder says its project lives. Nil when the folder does not record one.
public protocol XcodeRecords: Sendable {
    func workspacePath(ofDerivedData folder: CanonicalPath) -> String?
}

/// Simulators' answer, or why no answer is available.
public enum SimulatorReading: Equatable, Sendable {
    case notInstalled
    case unreadable(String)
    case read(SimulatorSnapshot)
}

/// One successful simulator reading.
public struct SimulatorSnapshot: Equatable, Sendable {
    public let devices: [SimulatorDevice]
    public let runtimes: [SimulatorRuntime]
    public let downloadAssets: [SimulatorAsset]
    public let stagingFolders: [CanonicalPath]

    public init(
        devices: [SimulatorDevice], runtimes: [SimulatorRuntime], downloadAssets: [SimulatorAsset],
        stagingFolders: [CanonicalPath]
    ) {
        self.devices = devices
        self.runtimes = runtimes
        self.downloadAssets = downloadAssets
        self.stagingFolders = stagingFolders
    }
}

/// One simulator `simctl list devices` reported.
public struct SimulatorDevice: Equatable, Sendable {
    public let udid: String
    public let name: String
    public let runtimeIdentifier: String
    public let isAvailable: Bool
    public let dataSize: ByteCount?

    public init(udid: String, name: String, runtimeIdentifier: String, isAvailable: Bool, dataSize: ByteCount?) {
        self.udid = udid
        self.name = name
        self.runtimeIdentifier = runtimeIdentifier
        self.isAvailable = isAvailable
        self.dataSize = dataSize
    }
}

/// One simulator runtime `simctl runtime list` reported.
public struct SimulatorRuntime: Equatable, Sendable {
    public let identifier: String
    public let runtimeIdentifier: String?
    public let version: String
    public let lastUsedAt: Instant?
    public let size: ByteCount?
    public let isDeletable: Bool
    public let assetFolder: CanonicalPath?

    public init(
        identifier: String, runtimeIdentifier: String?, version: String, lastUsedAt: Instant?, size: ByteCount?,
        isDeletable: Bool, assetFolder: CanonicalPath?
    ) {
        self.identifier = identifier
        self.runtimeIdentifier = runtimeIdentifier
        self.version = version
        self.lastUsedAt = lastUsedAt
        self.size = size
        self.isDeletable = isDeletable
        self.assetFolder = assetFolder
    }
}

/// A downloaded simulator runtime asset that may outlive the runtime which used it.
public struct SimulatorAsset: Equatable, Sendable {
    public let folder: CanonicalPath
    public let version: String?

    public init(folder: CanonicalPath, version: String?) {
        self.folder = folder
        self.version = version
    }
}

/// The Android SDK's answer, or why no answer is available.
public enum AndroidReading: Equatable, Sendable {
    case notInstalled
    case unreadable(String)
    case read(AndroidSnapshot)
}

/// One successful Android reading. The tool paths are nil when those command-line tools are not installed.
public struct AndroidSnapshot: Equatable, Sendable {
    public let sdkManager: CanonicalPath?
    public let avdManager: CanonicalPath?
    public let images: [AndroidImage]
    public let virtualDevices: [AndroidVirtualDevice]

    public init(
        sdkManager: CanonicalPath?, avdManager: CanonicalPath?, images: [AndroidImage],
        virtualDevices: [AndroidVirtualDevice]
    ) {
        self.sdkManager = sdkManager
        self.avdManager = avdManager
        self.images = images
        self.virtualDevices = virtualDevices
    }
}

/// One installed Android system image.
public struct AndroidImage: Equatable, Sendable {
    public let package: String
    public let folder: CanonicalPath

    public init(package: String, folder: CanonicalPath) {
        self.package = package
        self.folder = folder
    }
}

/// One Android virtual device. `imageFolder` is nil when its config names no system image.
public struct AndroidVirtualDevice: Equatable, Sendable {
    public let name: String
    public let folder: CanonicalPath
    public let imageFolder: CanonicalPath?

    public init(name: String, folder: CanonicalPath, imageFolder: CanonicalPath?) {
        self.name = name
        self.folder = folder
        self.imageFolder = imageFolder
    }
}
