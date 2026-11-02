import SharedKernel

/// Finds Cargo build folders in a scan, whatever they are called. Shared by the rules that look at Rust output.
///
/// A build folder holds `.rustc_info.json` and either `CACHEDIR.TAG` or a `debug` or `release` folder with Cargo's
/// `.cargo-lock`. Cargo writes `CACHEDIR.TAG` only when it creates the folder itself, so a shared `CARGO_TARGET_DIR`
/// made beforehand lacks it.
public enum RustBuildFolders {
    /// Build folders not nested inside another one, in path order.
    public static func outermost(in folders: [ScannedFolder]) -> [ScannedFolder] {
        var markersByPath: [String: Set<String>] = [:]
        for folder in folders { markersByPath[folder.path.raw] = folder.markers }
        let matches = folders.filter { isBuildFolder($0, markersByPath: markersByPath) }
        return matches
            .filter { folder in !matches.contains { $0.path != folder.path && folder.path.isSameOrDescendant(of: $0.path) } }
            .sorted { $0.path < $1.path }
    }

    /// Facts that identify the folder, for a candidate's evidence.
    public static func facts(for folder: ScannedFolder) -> [String] {
        folder.markers.contains("CACHEDIR.TAG")
            ? ["Holds CACHEDIR.TAG and .rustc_info.json."]
            : ["Holds .rustc_info.json, and its profile folder holds Cargo's .cargo-lock."]
    }

    private static func isBuildFolder(_ folder: ScannedFolder, markersByPath: [String: Set<String>]) -> Bool {
        guard folder.markers.contains(".rustc_info.json") else { return false }
        if folder.markers.contains("CACHEDIR.TAG") { return true }
        return ["debug", "release"].contains { profile in
            folder.path.appending(profile).flatMap { markersByPath[$0.raw] }?.contains(".cargo-lock") ?? false
        }
    }
}
