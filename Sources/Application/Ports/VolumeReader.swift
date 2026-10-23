import SharedKernel

public enum EntryType: Sendable, Equatable { case directory, file, symlink, other }

/// One directory entry as the bulk reader returns it.
public struct DirectoryEntry: Sendable, Equatable {
    public let name: String
    public let type: EntryType
    public let deviceID: Int32
    public let fileID: UInt64
    /// Directories only.
    public let isMountPoint: Bool
    /// Files and symlinks; 0 for directories.
    public let linkCount: UInt32
    /// Files and symlinks; `.zero` for directories.
    public let allocated: ByteCount
    /// Files; `.zero` otherwise.
    public let privateSize: ByteCount
    /// 0 when not returned.
    public let cloneID: UInt64
    /// 0 when not returned.
    public let cloneRefCount: UInt32
    public let modified: Instant

    public init(
        name: String, type: EntryType, deviceID: Int32, fileID: UInt64, isMountPoint: Bool, linkCount: UInt32,
        allocated: ByteCount, privateSize: ByteCount, cloneID: UInt64, cloneRefCount: UInt32, modified: Instant
    ) {
        self.name = name
        self.type = type
        self.deviceID = deviceID
        self.fileID = fileID
        self.isMountPoint = isMountPoint
        self.linkCount = linkCount
        self.allocated = allocated
        self.privateSize = privateSize
        self.cloneID = cloneID
        self.cloneRefCount = cloneRefCount
        self.modified = modified
    }
}

public enum DirectoryReadError: Error, Equatable, Sendable {
    /// `cloudOnly`: a dataless folder whose contents live only in the cloud; nothing in it is stored on this Mac.
    case permissionDenied, notPermitted, notFound, notADirectory, nameTooLong, cloudOnly, other(errno: Int32)
}

/// Raw capacity figures for one volume. RunScan translates them into the domain's `VolumeCapacity`.
public struct CapacityReading: Sendable, Equatable {
    public let total: ByteCount
    public let available: ByteCount
    public let availableForImportantUsage: ByteCount
    public let usedByVolume: ByteCount

    public init(total: ByteCount, available: ByteCount, availableForImportantUsage: ByteCount, usedByVolume: ByteCount) {
        self.total = total
        self.available = available
        self.availableForImportantUsage = availableForImportantUsage
        self.usedByVolume = usedByVolume
    }
}

public protocol VolumeReader: Sendable {
    /// Blocking. Never call it on Swift's cooperative thread pool (see ReadPool).
    func readDirectory(at path: CanonicalPath) throws(DirectoryReadError) -> [DirectoryEntry]
    /// lstat: never follows a symlink.
    func entryType(at path: CanonicalPath) throws(DirectoryReadError) -> EntryType
    func deviceID(of path: CanonicalPath) throws(DirectoryReadError) -> Int32
    /// The mount point of the volume holding `path` (statfs). Unlike the device id, it tells the System volume ("/")
    /// from the Data volume ("/System/Volumes/Data"), which share one APFS volume group.
    func mountPath(of path: CanonicalPath) throws(DirectoryReadError) -> CanonicalPath
    func capacity(ofVolumeAt mountPath: CanonicalPath) throws(DirectoryReadError) -> CapacityReading
}
