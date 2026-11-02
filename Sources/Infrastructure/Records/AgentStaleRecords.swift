import Catalog
import Darwin
import Foundation
import SharedKernel

/// Counts untouched `.rcgu.o` files and incremental caches in a Rust build folder.
///
/// Allocated bytes are summed once per inode. An inode counts toward what deletion would free only when every link
/// was inside this selection, so a hard link that is still in use keeps its bytes.
struct LiveStaleBuildRecords: StaleBuildRecords {
    func stale(in target: CanonicalPath, untouchedForSeconds: Int64, now: Instant) -> StaleReading {
        let limit = Self.cutoff(now: now, untouchedForSeconds: untouchedForSeconds)
        var inodes: [Inode: CountedInode] = [:]
        var entries = 0
        switch Self.objectFiles(in: target, olderThan: limit) {
        case .missing: break
        case .unreadable(let reason): return .unreadable(reason)
        case .found(let files):
            entries += files.count
            for file in files { Self.record(file, into: &inodes) }
        }
        switch Self.incrementalFolders(in: target, olderThan: limit) {
        case .missing: break
        case .unreadable(let reason): return .unreadable(reason)
        case .found(let folders, let files):
            entries += folders
            for file in files { Self.record(file, into: &inodes) }
        }
        let takesUp = inodes.values.reduce(UInt64(0)) { $0 + $1.allocated }
        let frees = inodes.values.reduce(UInt64(0)) { $0 + ($1.seen >= $1.nlink ? $1.allocated : 0) }
        return .read(entries: entries, takesUp: ByteCount(takesUp), freesAtLeast: ByteCount(min(frees, takesUp)))
    }

    private struct Inode: Hashable {
        var device: UInt64
        var number: UInt64
    }

    private struct CountedInode {
        var seen: Int
        var nlink: Int
        var allocated: UInt64
    }

    private struct FileStat {
        var device: UInt64
        var inode: UInt64
        var nlink: Int
        var allocated: UInt64
    }

    private enum FoundFiles {
        case missing
        case unreadable(String)
        case found([FileStat])
    }

    private enum FoundFolders {
        case missing
        case unreadable(String)
        case found(folders: Int, files: [FileStat])
    }

    private static func record(_ file: FileStat, into inodes: inout [Inode: CountedInode]) {
        let key = Inode(device: file.device, number: file.inode)
        if var existing = inodes[key] {
            existing.seen += 1
            inodes[key] = existing
        } else {
            inodes[key] = CountedInode(seen: 1, nlink: file.nlink, allocated: file.allocated)
        }
    }

    private static func objectFiles(in target: CanonicalPath, olderThan limit: Instant) -> FoundFiles {
        guard let deps = target.appending("debug")?.appending("deps") else { return .missing }
        switch presence(deps.raw) {
        case .missing: return .missing
        case .unreadable(let reason): return .unreadable(reason)
        case .directory: break
        }
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: deps.raw), includingPropertiesForKeys: nil) }
        catch { return .unreadable("Can't read \(deps.raw).") }
        var files: [FileStat] = []
        for child in children {
            guard child.lastPathComponent.hasSuffix(".rcgu.o") else { continue }
            switch file(child.path) {
            case .skip: continue
            case .unreadable(let reason): return .unreadable(reason)
            case .file(let info, let modified):
                guard modified <= limit else { continue }
                files.append(info)
            }
        }
        return .found(files)
    }

    private static func incrementalFolders(in target: CanonicalPath, olderThan limit: Instant) -> FoundFolders {
        guard let incremental = target.appending("debug")?.appending("incremental") else { return .missing }
        switch presence(incremental.raw) {
        case .missing: return .missing
        case .unreadable(let reason): return .unreadable(reason)
        case .directory: break
        }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: incremental.raw), includingPropertiesForKeys: nil
            )
        } catch { return .unreadable("Can't read \(incremental.raw).") }
        var folders = 0
        var files: [FileStat] = []
        for child in children {
            switch presence(child.path) {
            case .missing: continue
            case .unreadable(let reason): return .unreadable(reason)
            case .directory:
                switch newest(in: child, includingItself: true) {
                case .unreadable(let reason): return .unreadable(reason)
                case .time(let modified):
                    guard modified <= limit else { continue }
                    folders += 1
                    switch regularFiles(under: child) {
                    case .unreadable(let reason): return .unreadable(reason)
                    case .files(let found): files.append(contentsOf: found)
                    }
                }
            }
        }
        return .found(folders: folders, files: files)
    }

    private enum Presence { case missing, directory, unreadable(String) }

    private static func presence(_ path: String) -> Presence {
        var info = stat()
        if lstat(path, &info) != 0 {
            return errno == ENOENT ? .missing : .unreadable(String(cString: strerror(errno)))
        }
        return info.st_mode & S_IFMT == S_IFDIR ? .directory : .missing
    }

    private enum FileRead { case skip, unreadable(String), file(FileStat, Instant) }

    private static func file(_ path: String) -> FileRead {
        var info = stat()
        if lstat(path, &info) != 0 {
            return errno == ENOENT ? .skip : .unreadable(String(cString: strerror(errno)))
        }
        let kind = info.st_mode & S_IFMT
        guard kind == S_IFREG else { return .skip }
        let allocated = info.st_blocks > 0 ? UInt64(info.st_blocks) * 512 : 0
        let stat = FileStat(
            device: UInt64(info.st_dev), inode: UInt64(info.st_ino), nlink: Int(info.st_nlink), allocated: allocated
        )
        let modified = Instant(seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
        return .file(stat, modified)
    }

    private enum Newest { case time(Instant), unreadable(String) }

    private static func newest(in directory: URL, includingItself: Bool) -> Newest {
        var latest: Instant?
        if includingItself {
            switch file(directory.path) {
            case .unreadable(let reason): return .unreadable(reason)
            case .skip:
                var info = stat()
                if lstat(directory.path, &info) == 0 {
                    latest = Instant(seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
                }
            case .file(_, let modified): latest = modified
            }
        }
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch { return .unreadable("Can't read \(directory.path).") }
        for child in children {
            var info = stat()
            if lstat(child.path, &info) != 0 {
                if errno == ENOENT { continue }
                return .unreadable(String(cString: strerror(errno)))
            }
            let modified = Instant(seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
            if latest == nil || modified > latest! { latest = modified }
            if info.st_mode & S_IFMT == S_IFDIR {
                switch newest(in: child, includingItself: false) {
                case .unreadable(let reason): return .unreadable(reason)
                case .time(let nested):
                    if latest == nil || nested > latest! { latest = nested }
                }
            }
        }
        return .time(latest ?? Instant(nanosecondsSince1970: 0))
    }

    private enum Files { case files([FileStat]), unreadable(String) }

    private static func regularFiles(under directory: URL) -> Files {
        var found: [FileStat] = []
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch { return .unreadable("Can't read \(directory.path).") }
        for child in children {
            var info = stat()
            if lstat(child.path, &info) != 0 {
                if errno == ENOENT { continue }
                return .unreadable(String(cString: strerror(errno)))
            }
            if info.st_mode & S_IFMT == S_IFDIR {
                switch regularFiles(under: child) {
                case .unreadable(let reason): return .unreadable(reason)
                case .files(let nested): found.append(contentsOf: nested)
                }
                continue
            }
            guard info.st_mode & S_IFMT == S_IFREG else { continue }
            let allocated = info.st_blocks > 0 ? UInt64(info.st_blocks) * 512 : 0
            found.append(FileStat(
                device: UInt64(info.st_dev), inode: UInt64(info.st_ino), nlink: Int(info.st_nlink), allocated: allocated
            ))
        }
        return .files(found)
    }

    private static func cutoff(now: Instant, untouchedForSeconds: Int64) -> Instant {
        let (delta, overflowed) = untouchedForSeconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflowed else { return Instant(nanosecondsSince1970: .min) }
        let (value, under) = now.nanosecondsSince1970.subtractingReportingOverflow(delta)
        return Instant(nanosecondsSince1970: under ? .min : value)
    }
}
