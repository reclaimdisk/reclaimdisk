import Foundation
import Inventory
import SharedKernel

public struct ScanOptions: Sendable {
    /// A path to READ (for the whole volume: /System/Volumes/Data).
    public var root: CanonicalPath
    public var classifier: KindClassifier
    /// Folders and files smaller than this are folded into per-kind aggregates.
    public var minimumNodeSize: ByteCount
    /// Names of files whose presence is recorded on their folder (`NodeDraft.markers`).
    public var markerFileNames: Set<String>
    /// Folders with these names are always kept, whatever their size.
    public var retainedDirectoryNames: Set<String>
    public var maxConcurrentReads: Int

    public init(
        root: CanonicalPath, classifier: KindClassifier, minimumNodeSize: ByteCount = ByteCount(268_435_456),
        markerFileNames: Set<String> = ["CACHEDIR.TAG", ".rustc_info.json"], retainedDirectoryNames: Set<String> = [],
        maxConcurrentReads: Int = ProcessInfo.processInfo.activeProcessorCount
    ) {
        self.root = root
        self.classifier = classifier
        self.minimumNodeSize = minimumNodeSize
        self.markerFileNames = markerFileNames
        self.retainedDirectoryNames = retainedDirectoryNames
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
