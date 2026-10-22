import Darwin
import Foundation
import Infrastructure
import SharedKernel

/// A fresh, resolved temp folder for one test, removed afterwards.
final class TempFolder {
    let path: CanonicalPath
    var url: URL { URL(fileURLWithPath: path.raw) }

    init() throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("reclaimdisk-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        path = try PathResolver.resolve(raw.path, currentDirectory: .root)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func child(_ name: String) -> CanonicalPath { path.appending(name)! }

    @discardableResult
    func writeRandom(_ name: String, bytes: Int) throws -> CanonicalPath {
        var data = [UInt8](repeating: 0, count: bytes)
        arc4random_buf(&data, bytes)
        try Data(data).write(to: url.appendingPathComponent(name))
        return child(name)
    }

    func clone(_ source: String, to destination: String) throws {
        guard clonefile(child(source).raw, child(destination).raw, 0) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
    }

    func hardLink(_ source: String, to destination: String) throws {
        guard link(child(source).raw, child(destination).raw) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
    }

    func overwriteStart(of name: String, bytes: Int) throws {
        let fd = open(child(name).raw, O_WRONLY)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        defer { close(fd) }
        var data = [UInt8](repeating: 0, count: bytes)
        arc4random_buf(&data, bytes)
        guard pwrite(fd, data, bytes, 0) == bytes, fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
    }

    func mkdir(_ name: String) throws { try FileManager.default.createDirectory(at: url.appendingPathComponent(name), withIntermediateDirectories: false) }
}
