import Application
import Darwin
import Foundation
import SharedKernel

/// The real `VolumeReader`: getattrlistbulk for directories, lstat for single entries, statfs for capacity.
public struct DarwinVolumeReader: VolumeReader {
    private static let bufferSize = 256 * 1024

    public init() {}

    public func readDirectory(at path: CanonicalPath) throws(DirectoryReadError) -> [DirectoryEntry] {
        let fd = open(path.raw, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw Self.error(for: errno) }
        defer { close(fd) }
        var request = BulkAttributeParser.request()
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        var entries: [DirectoryEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, Self.bufferSize, UInt64(FSOPT_ATTR_CMN_EXTENDED))
            if count < 0 { throw Self.error(for: errno) }
            if count == 0 { return entries }
            entries += BulkAttributeParser.parse(UnsafeRawBufferPointer(start: buffer, count: Self.bufferSize), count: Int(count))
        }
    }

    public func entryType(at path: CanonicalPath) throws(DirectoryReadError) -> EntryType {
        var info = stat()
        guard lstat(path.raw, &info) == 0 else { throw Self.error(for: errno) }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFREG: return .file
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    public func deviceID(of path: CanonicalPath) throws(DirectoryReadError) -> Int32 {
        var info = stat()
        guard lstat(path.raw, &info) == 0 else { throw Self.error(for: errno) }
        return info.st_dev
    }

    public func mountPath(of path: CanonicalPath) throws(DirectoryReadError) -> CanonicalPath {
        var info = statfs()
        guard statfs(path.raw, &info) == 0 else { throw Self.error(for: errno) }
        let mount = withUnsafeBytes(of: &info.f_mntonname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard let mountPath = CanonicalPath(mount) else { throw .other(errno: EINVAL) }
        return mountPath
    }

    public func capacity(ofVolumeAt mountPath: CanonicalPath) throws(DirectoryReadError) -> CapacityReading {
        var info = statfs()
        guard statfs(mountPath.raw, &info) == 0 else { throw Self.error(for: errno) }
        let blockSize = UInt64(info.f_bsize)
        let total = UInt64(info.f_blocks) * blockSize
        let available = UInt64(info.f_bavail) * blockSize
        let used = (UInt64(info.f_blocks) - UInt64(info.f_bfree)) * blockSize
        // Docs: https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey
        let important = (try? URL(fileURLWithPath: mountPath.raw)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage)
            .flatMap { $0 }
            .map { UInt64(max(0, $0)) } ?? available
        return CapacityReading(
            total: ByteCount(total), available: ByteCount(available),
            availableForImportantUsage: ByteCount(important), usedByVolume: ByteCount(used)
        )
    }

    static func error(for code: Int32) -> DirectoryReadError {
        switch code {
        case EACCES: .permissionDenied
        case EPERM: .notPermitted
        case ENOENT: .notFound
        case ENOTDIR, ELOOP: .notADirectory
        case ENAMETOOLONG: .nameTooLong
        default: .other(errno: code)
        }
    }
}
