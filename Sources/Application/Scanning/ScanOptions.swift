import Foundation
import Inventory
import SharedKernel

public struct ScanOptions: Sendable {
    /// A path to READ (for the whole volume: /System/Volumes/Data).
    public var root: CanonicalPath
    public var classifier: KindClassifier
    /// Folders and files smaller than this are folded into per-kind aggregates.
    public var minimumNodeSize: ByteCount
    /// Names of files whose presence keeps the folder and is recorded on it (`NodeDraft.markers`).
    public var markerFileNames: Set<String>
    /// Recorded on the folder, and never a reason to keep it. Project files such as package.json and lockfiles.
    public var recordedMarkerFileNames: Set<String>
    /// Kept when the folder's total is at least `retainedMinimumSize` and no ancestor below the scan root
    /// has one of these names or a force-kept marker.
    public var retainedDirectoryNames: Set<String>
    /// A retained-name folder smaller than this is folded like any other small folder.
    public var retainedMinimumSize: ByteCount
    public var maxConcurrentReads: Int

    public init(
        root: CanonicalPath, classifier: KindClassifier, minimumNodeSize: ByteCount = ByteCount(268_435_456),
        markerFileNames: Set<String> = ["CACHEDIR.TAG", ".rustc_info.json", ".cargo-lock"],
        recordedMarkerFileNames: Set<String> = [
            "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb",
            "pyvenv.cfg", "uv.lock", "poetry.lock", "requirements.txt", "requirements-dev.txt", "Cargo.toml",
            "build.gradle", "build.gradle.kts",
        ],
        retainedDirectoryNames: Set<String> = [
            "node_modules", ".next", ".turbo", ".parcel-cache", ".svelte-kit", ".nuxt", ".venv", "venv",
        ],
        retainedMinimumSize: ByteCount = .mebibyte,
        maxConcurrentReads: Int = ProcessInfo.processInfo.activeProcessorCount
    ) {
        self.root = root
        self.classifier = classifier
        self.minimumNodeSize = minimumNodeSize
        self.markerFileNames = markerFileNames
        self.recordedMarkerFileNames = recordedMarkerFileNames
        self.retainedDirectoryNames = retainedDirectoryNames
        self.retainedMinimumSize = retainedMinimumSize
        self.maxConcurrentReads = maxConcurrentReads
    }
}

public struct ScanProgress: Sendable, Equatable {
    public let directoriesRead: Int
    public let bytesSeen: ByteCount
    public let currentPath: CanonicalPath?

    public init(directoriesRead: Int, bytesSeen: ByteCount, currentPath: CanonicalPath?) {
        self.directoriesRead = directoriesRead
        self.bytesSeen = bytesSeen
        self.currentPath = currentPath
    }
}

public struct ScanBuildResult: Sendable, Equatable {
    public let root: NodeDraft
    public let unreadable: [UnreadableArea]
    public let scannedUniqueBytes: ByteCount
    public let startedAt: Instant
    public let finishedAt: Instant
}

public enum ScanBuildError: Error, Equatable, Sendable {
    case rootUnreadable(DirectoryReadError)
}
