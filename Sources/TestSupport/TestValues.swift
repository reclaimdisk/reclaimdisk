import Application
import Inventory
import SharedKernel

public func mib(_ n: UInt64) -> ByteCount { ByteCount(n * 1_048_576) }

/// Builders for `DirectoryEntry` values in tests.
public enum Entry {
    public static func file(
        _ name: String, allocated: ByteCount, private privateSize: ByteCount? = nil, fileID: UInt64,
        links: UInt32 = 1, cloneID: UInt64 = 0, refCount: UInt32 = 0, device: Int32 = 1,
        modified: Instant = Instant(nanosecondsSince1970: 0)
    ) -> DirectoryEntry {
        DirectoryEntry(
            name: name, type: .file, deviceID: device, fileID: fileID, isMountPoint: false, linkCount: links,
            allocated: allocated, privateSize: privateSize ?? allocated, cloneID: cloneID, cloneRefCount: refCount,
            modified: modified
        )
    }

    public static func dir(
        _ name: String, fileID: UInt64 = 0, device: Int32 = 1, mountPoint: Bool = false,
        modified: Instant = Instant(nanosecondsSince1970: 0)
    ) -> DirectoryEntry {
        DirectoryEntry(
            name: name, type: .directory, deviceID: device, fileID: fileID, isMountPoint: mountPoint, linkCount: 0,
            allocated: .zero, privateSize: .zero, cloneID: 0, cloneRefCount: 0, modified: modified
        )
    }

    public static func symlink(_ name: String, fileID: UInt64 = 0, device: Int32 = 1) -> DirectoryEntry {
        DirectoryEntry(
            name: name, type: .symlink, deviceID: device, fileID: fileID, isMountPoint: false, linkCount: 1,
            allocated: .zero, privateSize: .zero, cloneID: 0, cloneRefCount: 0, modified: Instant(nanosecondsSince1970: 0)
        )
    }
}

/// The classifier tests use: home is /Users/u.
public let testClassifier = KindClassifier(home: CanonicalPath("/Users/u")!)
