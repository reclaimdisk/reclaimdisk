import Application
import Darwin
import Foundation
import SharedKernel

public enum PathResolver {
    /// Joins a relative input with `currentDirectory`, then resolves it with realpath(3): symlinks (including the last
    /// component), "." and ".." are resolved. Throws `.notFound` for a missing path.
    public static func resolve(_ input: String, currentDirectory: CanonicalPath) throws(DirectoryReadError) -> CanonicalPath {
        let joined: String
        if input.hasPrefix("/") {
            joined = input
        } else {
            joined = currentDirectory == .root ? "/" + input : currentDirectory.raw + "/" + input
        }
        guard let resolved = realpath(joined, nil) else { throw DarwinVolumeReader.error(for: errno) }
        defer { free(resolved) }
        guard let path = CanonicalPath(String(cString: resolved)) else { throw .other(errno: EINVAL) }
        return path
    }

    /// The current user's home folder, resolved.
    public static func homeDirectory() -> CanonicalPath {
        let home = NSHomeDirectory()
        return (try? resolve(home, currentDirectory: .root)) ?? CanonicalPath(home) ?? .root
    }
}
