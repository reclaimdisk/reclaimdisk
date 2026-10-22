import Application
import Darwin
import SharedKernel

/// Builds the `getattrlistbulk` request and parses its buffer. Layout verified on 2026-10-22 (plan, "Verified facts"):
/// u32 length | attribute_set_t | [u32 error] | attrreference name | u32 devid | u32 objtype | timespec modtime | u64 fileid
/// | [dir: u32 mountstatus] | [file: u32 linkcount, u64 allocsize] | [ext: u64 privatesize, u64 cloneid, u64 extflags, u32 refcnt].
/// Optional fields are present only when their bit is set in the returned set.
enum BulkAttributeParser {
    static func request() -> attrlist {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(bitPattern: Int32(bitPattern: ATTR_CMN_RETURNED_ATTRS))
            | attrgroup_t(ATTR_CMN_NAME | ATTR_CMN_ERROR | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FILEID)
        list.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS | ATTR_CMNEXT_CLONE_REFCNT)
        return list
    }

    /// Parses `count` entries from one `getattrlistbulk` call. Entries with a per-entry error are skipped.
    static func parse(_ buffer: UnsafeRawBufferPointer, count: Int) -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        entries.reserveCapacity(count)
        var entryStart = 0
        for _ in 0..<count {
            let length = Int(buffer.loadUnaligned(fromByteOffset: entryStart, as: UInt32.self))
            defer { entryStart += length }
            var field = entryStart + 4
            func u32() -> UInt32 { defer { field += 4 }; return buffer.loadUnaligned(fromByteOffset: field, as: UInt32.self) }
            func u64() -> UInt64 { defer { field += 8 }; return buffer.loadUnaligned(fromByteOffset: field, as: UInt64.self) }

            let returned = buffer.loadUnaligned(fromByteOffset: field, as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size
            let error = (returned.commonattr & attrgroup_t(ATTR_CMN_ERROR)) != 0 ? u32() : 0

            let nameField = field
            let nameOffset = Int(buffer.loadUnaligned(fromByteOffset: field, as: Int32.self))
            let nameLength = Int(buffer.loadUnaligned(fromByteOffset: field + 4, as: UInt32.self))
            field += 8
            guard error == 0 else { continue }
            let nameStart = nameField + nameOffset
            let nameBytes = UnsafeRawBufferPointer(rebasing: buffer[nameStart..<(nameStart + max(0, nameLength - 1))])
            let name = String(decoding: nameBytes, as: UTF8.self)

            let deviceID = Int32(bitPattern: u32())
            let objectType = u32()
            let seconds = Int64(bitPattern: u64())
            let nanoseconds = Int64(bitPattern: u64())
            let fileID = u64()
            var mountStatus: UInt32 = 0, linkCount: UInt32 = 0, allocated: UInt64 = 0
            if (returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS)) != 0 { mountStatus = u32() }
            if (returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT)) != 0 { linkCount = u32() }
            if (returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE)) != 0 { allocated = u64() }
            func has(_ bit: Int32) -> Bool { (returned.forkattr & attrgroup_t(bit)) != 0 }
            let privateSize = has(ATTR_CMNEXT_PRIVATESIZE) ? u64() : 0
            let cloneID = has(ATTR_CMNEXT_CLONEID) ? u64() : 0
            _ = has(ATTR_CMNEXT_EXT_FLAGS) ? u64() : 0
            let cloneRefCount = has(ATTR_CMNEXT_CLONE_REFCNT) ? u32() : 0

            let type: EntryType = switch objectType {
            case VDIR.rawValue: .directory
            case VREG.rawValue: .file
            case VLNK.rawValue: .symlink
            default: .other
            }
            let isDirectory = type == .directory
            entries.append(DirectoryEntry(
                name: name, type: type, deviceID: deviceID, fileID: fileID,
                isMountPoint: isDirectory && (mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT)) != 0,
                linkCount: isDirectory ? 0 : linkCount,
                allocated: isDirectory ? .zero : ByteCount(allocated),
                privateSize: type == .file ? ByteCount(privateSize) : .zero,
                cloneID: cloneID, cloneRefCount: cloneRefCount,
                modified: Instant(seconds: seconds, nanoseconds: nanoseconds)
            ))
        }
        return entries
    }
}
