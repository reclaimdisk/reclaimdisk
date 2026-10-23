import Inventory
import SharedKernel

public struct ScanRequest: Sendable, Equatable {
    /// nil = the whole Data volume; otherwise an absolute, already-resolved folder.
    public var path: CanonicalPath?
    public var minimumNodeSize: ByteCount

    public init(path: CanonicalPath? = nil, minimumNodeSize: ByteCount = ByteCount(268_435_456)) {
        self.path = path
        self.minimumNodeSize = minimumNodeSize
    }
}

public enum ScanError: Error, Equatable, Sendable {
    case notADirectory(CanonicalPath)
    case notOnDataVolume(CanonicalPath)
    case unreadable(CanonicalPath, DirectoryReadError)
    case inconsistentMeasurement(String)
}

/// The scan use case: checks the request, reads the disk layout, walks the folders and validates the result.
public struct RunScan: Sendable {
    public static let dataVolume = CanonicalPath("/System/Volumes/Data")!
    public static let swapVolume = CanonicalPath("/System/Volumes/VM")!
    public static let lowDiskThreshold = ByteCount.gibibyte

    private let reader: any VolumeReader
    private let clock: any WallClock
    private let home: CanonicalPath

    public init(reader: any VolumeReader, clock: any WallClock, home: CanonicalPath) {
        self.reader = reader
        self.clock = clock
        self.home = home
    }

    /// Throws only `ScanError` or `CancellationError`.
    public func callAsFunction(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Scan {
        let disk = try await Blocking.run { () throws(ScanError) in try self.preflight() }
        let root: CanonicalPath
        if let path = request.path {
            try await Blocking.run { () throws(ScanError) in try self.checkFolder(path) }
            root = path
        } else {
            root = Self.dataVolume
        }

        let classifier = KindClassifier(home: home)
        let options = ScanOptions(root: root, classifier: classifier, minimumNodeSize: request.minimumNodeSize)
        let result: ScanBuildResult
        do {
            result = try await ScanBuilder(reader: reader, clock: clock).build(options, progress: progress)
        } catch let ScanBuildError.rootUnreadable(error) {
            throw ScanError.unreadable(root, error)
        }

        do {
            return try Scan(
                volumeMountPath: Self.dataVolume, root: result.root, disk: disk, startedAt: result.startedAt,
                finishedAt: result.finishedAt, unreadable: result.unreadable, scannedUniqueBytes: result.scannedUniqueBytes,
                isWholeVolume: request.path == nil, classifier: classifier
            )
        } catch {
            throw ScanError.inconsistentMeasurement(String(describing: error))
        }
    }

    /// Reads the disk layout without scanning. Front ends call it first and warn when data.available < lowDiskThreshold.
    public func preflight() throws(ScanError) -> DiskLayout {
        let reading: CapacityReading
        do { reading = try reader.capacity(ofVolumeAt: Self.dataVolume) } catch { throw .unreadable(Self.dataVolume, error) }
        let data: VolumeCapacity
        do {
            data = try VolumeCapacity(
                total: reading.total, available: reading.available,
                availableIncludingPurgeable: reading.availableForImportantUsage, usedByVolume: reading.usedByVolume
            )
        } catch {
            throw .inconsistentMeasurement(String(describing: error))
        }
        let swap = try? reader.capacity(ofVolumeAt: Self.swapVolume).usedByVolume
        return DiskLayout(data: data, swapUsed: swap)
    }

    /// The folder must exist, be a directory (callers resolve symlinks first) and sit on the Data volume.
    /// The volume is decided by mount point: the System and Data volumes share one device id.
    private func checkFolder(_ path: CanonicalPath) throws(ScanError) {
        let type: EntryType
        do { type = try reader.entryType(at: path) } catch { throw .unreadable(path, error) }
        guard type == .directory else { throw .notADirectory(path) }
        let mount: CanonicalPath
        do { mount = try reader.mountPath(of: path) } catch { throw .unreadable(path, error) }
        guard mount == Self.dataVolume else { throw .notOnDataVolume(path) }
    }
}
