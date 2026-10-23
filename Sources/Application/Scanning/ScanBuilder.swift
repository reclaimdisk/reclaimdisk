import Inventory
import SharedKernel

/// Walks one folder tree breadth-first and builds the kept node tree.
public struct ScanBuilder: Sendable {
    private static let progressInterval: Int64 = 250_000_000
    private static let dataVolume = CanonicalPath("/System/Volumes/Data")!

    private let reader: any VolumeReader
    private let clock: any WallClock

    public init(reader: any VolumeReader, clock: any WallClock) {
        self.reader = reader
        self.clock = clock
    }

    /// Throws `ScanBuildError.rootUnreadable`, or `CancellationError`.
    public func build(_ options: ScanOptions, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanBuildResult {
        let startedAt = clock.now()
        let pool = ReadPool(reader: reader)
        let rootDevice: Int32
        switch await pool.deviceID(of: options.root) {
        case .success(let device): rootDevice = device
        case .failure(let error): throw ScanBuildError.rootUnreadable(error)
        }

        let rootName = options.root == Self.dataVolume ? "Data volume" : options.root.lastComponent
        var table = DirectoryTable(rootName: rootName)
        var accounting = LinkAndCloneAccounting()
        var queue: [(folder: Int32, path: CanonicalPath)] = [(0, options.root)]
        var head = 0
        var directoriesRead = 0
        var bytesSeen: UInt64 = 0
        var lastProgress = startedAt
        let window = max(1, options.maxConcurrentReads)

        try await withThrowingTaskGroup(of: (Int32, CanonicalPath, Result<[DirectoryEntry], DirectoryReadError>).self) { group in
            var inFlight = 0
            while true {
                while inFlight < window, head < queue.count {
                    try Task.checkCancellation()
                    let (folder, path) = queue[head]
                    head += 1
                    group.addTask { (folder, path, await pool.readDirectory(at: path)) }
                    inFlight += 1
                }
                if head > 65_536 {   // drop launched entries so the queue doesn't hold every path
                    queue.removeFirst(head)
                    head = 0
                }
                guard inFlight > 0, let (folder, path, result) = try await group.next() else { break }
                inFlight -= 1
                directoriesRead += 1

                switch result {
                case .success(let entries):
                    for entry in entries {
                        table.newestOwn[Int(folder)] = max(table.newestOwn[Int(folder)], entry.modified.nanosecondsSince1970)
                        switch entry.type {
                        case .directory:
                            guard !entry.isMountPoint, entry.deviceID == rootDevice, let childPath = path.appending(entry.name) else { continue }
                            let child = table.addFolder(named: entry.name, parent: folder)
                            queue.append((child, childPath))
                        case .file, .symlink:
                            bytesSeen += entry.allocated.bytes
                            // "Frees at least" can never exceed what the file occupies; clamp so one odd value can't fail the scan.
                            let privateBytes = min(entry.privateSize.bytes, entry.allocated.bytes)
                            if entry.type == .file, options.markerFileNames.contains(entry.name) {
                                table.markers[folder, default: []].insert(entry.name)
                            }
                            if entry.type == .file, entry.cloneRefCount > 1 {
                                accounting.recordClone(cloneID: entry.cloneID, fileID: entry.fileID, allocated: entry.allocated.bytes)
                            }
                            if entry.type == .file, entry.linkCount > 1 {
                                accounting.recordLink(fileID: entry.fileID, linkCount: entry.linkCount, allocated: entry.allocated.bytes,
                                                      privateSize: privateBytes, folder: folder, name: entry.name)
                                continue
                            }
                            if entry.type == .file, entry.allocated >= options.minimumNodeSize {
                                table.largeFiles[folder, default: []].append(DirectoryTable.LargeFile(
                                    name: entry.name, takesUp: entry.allocated.bytes, freesAtLeast: privateBytes,
                                    modified: entry.modified.nanosecondsSince1970))
                            } else {
                                table.ownTakesUp[Int(folder)] += entry.allocated.bytes
                                table.ownFreesAtLeast[Int(folder)] += privateBytes
                            }
                        case .other:
                            continue
                        }
                    }
                case .failure(let error):
                    if folder == 0 { throw ScanBuildError.rootUnreadable(error) }
                    table.excluded[Int(folder)] = true
                    if let reason = Self.unreadableReason(for: error) { table.unreadable.append((folder, reason)) }
                }

                let now = clock.now()
                if now.nanosecondsSince1970 - lastProgress.nanosecondsSince1970 >= Self.progressInterval {
                    lastProgress = now
                    progress(ScanProgress(directoriesRead: directoriesRead, bytesSeen: ByteCount(bytesSeen), currentPath: DisplayPath.forReadPath(path)))
                }
            }
        }

        accounting.applyLinks(to: &table)   // before classification and folding (Task 8, rule 3)
        let rootDisplayPath = DisplayPath.forReadPath(options.root)
        let root = Folding.rootDraft(table: table, options: options, rootDisplayPath: rootDisplayPath)
        let unreadable = table.unreadable
            .compactMap { item in table.readPath(of: item.folder, root: options.root).map { UnreadableArea(path: DisplayPath.forReadPath($0), reason: item.reason) } }
            .sorted { $0.path < $1.path }
        progress(ScanProgress(directoriesRead: directoriesRead, bytesSeen: ByteCount(bytesSeen), currentPath: nil))
        return ScanBuildResult(
            root: root, unreadable: unreadable,
            scannedUniqueBytes: root.totalTakesUp.subtractingClamped(ByteCount(accounting.cloneDuplicateBytes)),
            startedAt: startedAt, finishedAt: clock.now()
        )
    }

    /// nil for errors that mean "the folder is gone", which are skipped silently.
    private static func unreadableReason(for error: DirectoryReadError) -> UnreadableReason? {
        switch error {
        case .permissionDenied: .permissionDenied
        case .notPermitted: .notPermitted
        case .nameTooLong: .pathTooLong
        case .other: .other
        case .notFound, .notADirectory: nil
        }
    }
}

extension NodeDraft {
    /// Own bytes plus all descendants.
    var totalTakesUp: ByteCount { children.reduce(ownTakesUp) { $0 + $1.totalTakesUp } }
}
