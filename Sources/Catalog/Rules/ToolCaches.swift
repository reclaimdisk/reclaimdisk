import SharedKernel

/// A read-only look at Docker. Implementations may run query commands; they never remove anything.
public protocol DockerRecords: Sendable {
    func read() -> DockerReading
}

/// A read-only look at package-manager cache folders.
public protocol PackageCacheRecords: Sendable {
    func read() -> [PackageCacheReading]
}

/// Docker's answer, or why no answer is available.
public enum DockerReading: Equatable, Sendable {
    case notInstalled
    case notResponding(String)
    case unparseable(String)
    case read(DockerSnapshot)
}

/// One successful Docker reading.
public struct DockerSnapshot: Equatable, Sendable {
    public let buildCacheReclaimable: ByteCount
    public let images: [DockerImage]
    public let volumes: [DockerVolume]
    public let anonymousVolumesReclaimable: ByteCount
    public let diskFile: DockerDiskFile?

    public init(
        buildCacheReclaimable: ByteCount, images: [DockerImage], volumes: [DockerVolume],
        anonymousVolumesReclaimable: ByteCount, diskFile: DockerDiskFile?
    ) {
        self.buildCacheReclaimable = buildCacheReclaimable
        self.images = images
        self.volumes = volumes
        self.anonymousVolumesReclaimable = anonymousVolumesReclaimable
        self.diskFile = diskFile
    }
}

/// One image `docker image ls` reported.
public struct DockerImage: Equatable, Sendable {
    public let id: String
    public let reference: String
    public let createdAt: Instant
    public let size: ByteCount
    public let usedByContainer: Bool

    public init(id: String, reference: String, createdAt: Instant, size: ByteCount, usedByContainer: Bool) {
        self.id = id
        self.reference = reference
        self.createdAt = createdAt
        self.size = size
        self.usedByContainer = usedByContainer
    }
}

/// One volume `docker volume ls` reported.
public struct DockerVolume: Equatable, Sendable {
    public let name: String
    public let isAnonymous: Bool
    public let usedByContainer: Bool

    public init(name: String, isAnonymous: Bool, usedByContainer: Bool) {
        self.name = name
        self.isAnonymous = isAnonymous
        self.usedByContainer = usedByContainer
    }
}

/// Docker Desktop's virtual disk. `allocated` is what it takes on the host; `maximum` is the file's full size.
public struct DockerDiskFile: Equatable, Sendable {
    public let path: CanonicalPath
    public let allocated: ByteCount
    public let maximum: ByteCount

    public init(path: CanonicalPath, allocated: ByteCount, maximum: ByteCount) {
        self.path = path
        self.allocated = allocated
        self.maximum = maximum
    }
}

/// Whether one package manager's cache could be read.
public enum PackageCacheReading: Equatable, Sendable {
    case notInstalled(tool: String)
    case unparseable(tool: String, reason: String)
    /// `found` still does not mean the folder is large enough to list; the rule checks the scan.
    case found(PackageCache)
}

/// A package manager's cache folder and the command that would clean it. Describing the command does not run it.
public struct PackageCache: Equatable, Sendable {
    public let tool: String
    public let folder: CanonicalPath
    public let clean: ToolCommand
    public let clearsWholeFolder: Bool
    public let busyReason: String?

    public init(tool: String, folder: CanonicalPath, clean: ToolCommand, clearsWholeFolder: Bool, busyReason: String?) {
        self.tool = tool
        self.folder = folder
        self.clean = clean
        self.clearsWholeFolder = clearsWholeFolder
        self.busyReason = busyReason
    }
}
