import Catalog
import Darwin
import Foundation
import SharedKernel

/// The current user's processes, by short name and working directory. A failed listing is unreadable rather than empty,
/// so a rule does not assume nothing is running.
struct LiveProcessRecords: ProcessRecords {
    func processes() -> ProcessReading {
        let uid = getuid()
        guard let pids = Self.pids(uid: uid) else { return .unreadable("Can't list running processes.") }
        var running: [RunningProcess] = []
        running.reserveCapacity(pids.count)
        for pid in pids {
            guard let name = Self.name(pid), !name.isEmpty else { continue }
            running.append(RunningProcess(name: name, workingDirectory: Self.workingDirectory(pid)))
        }
        return .read(running)
    }

    private static func pids(uid: uid_t) -> [pid_t]? {
        var capacity = 256
        for _ in 0..<8 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let written = proc_listpids(UInt32(PROC_UID_ONLY), uid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.stride))
            if written < 0 { return nil }
            let count = Int(written) / MemoryLayout<pid_t>.stride
            if count < buffer.count {
                return buffer.prefix(count).filter { $0 > 0 }
            }
            capacity *= 2
        }
        return nil
    }

    private static func name(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func workingDirectory(_ pid: pid_t) -> CanonicalPath? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let raw = withUnsafePointer(to: info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        guard !raw.isEmpty else { return nil }
        if let resolved = realpath(raw, nil) {
            defer { free(resolved) }
            if let path = CanonicalPath(String(cString: resolved)) { return path }
        }
        return CanonicalPath(raw)
    }
}
