import Foundation
import SharedKernel

/// Read-only directory lookups shared by the simulator and Android readers.
enum RuntimeFiles {
    enum DirectoryListing {
        case missing
        case unreadable
        case listed([CanonicalPath])
    }

    static func canonical(_ raw: String) -> CanonicalPath? {
        let trimmed = trimmingTrailingSlash(raw)
        if let resolved = try? PathResolver.resolve(trimmed, currentDirectory: .root) { return resolved }
        return CanonicalPath(trimmed)
    }

    static func directoryExists(_ path: CanonicalPath) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path.raw, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func fileExists(_ path: CanonicalPath) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path.raw, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// Direct child directories. A symlink to a directory counts. `resolveSymlinks` stores the link's target.
    static func childDirectories(
        _ directory: CanonicalPath, resolveSymlinks: Bool, where include: (String) -> Bool = { _ in true }
    ) -> DirectoryListing {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.raw, isDirectory: &isDirectory) else { return .missing }
        guard isDirectory.boolValue else { return .missing }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.raw)
        } catch {
            return .unreadable
        }
        var children: [CanonicalPath] = []
        for name in names where include(name) {
            guard let child = directory.appending(name) else { continue }
            var childIsDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: child.raw, isDirectory: &childIsDirectory), childIsDirectory.boolValue
            else { continue }
            let stored = resolveSymlinks ? (canonical(child.raw) ?? child) : child
            children.append(stored)
        }
        return .listed(children.sorted { $0.raw < $1.raw })
    }

    /// True when the folder contains `source.properties` or any other file. A folder of only subfolders does not.
    static func containsFile(_ directory: CanonicalPath) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.raw) else { return false }
        if names.contains("source.properties") { return true }
        for name in names {
            guard let child = directory.appending(name) else { continue }
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: child.raw, isDirectory: &isDirectory), !isDirectory.boolValue { return true }
        }
        return false
    }

    static func temporaryDirectory() -> CanonicalPath? {
        canonical(FileManager.default.temporaryDirectory.path)
    }
}

private func trimmingTrailingSlash(_ raw: String) -> String {
    var text = raw
    while text.count > 1, text.hasSuffix("/") { text.removeLast() }
    return text
}
