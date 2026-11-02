import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let twoDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 172_800) * second)

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private func folder(_ path: String, markers: Set<String>) -> ScannedFolder {
    ScannedFolder(path: CanonicalPath(path)!, kind: .buildOutput, takesUp: ByteCount(1_000), freesAtLeast: ByteCount(900),
                  newestChange: twoDaysAgo, markers: markers, parentMarkers: [])!
}

/// A CARGO_TARGET_DIR made with mkdir before Cargo ran has .rustc_info.json but no CACHEDIR.TAG (Cargo writes the tag only
/// when it creates the folder itself); its profile folders still hold Cargo's .cargo-lock.
private let layout = [
    folder("/Users/u/Projects/rc/.worktrees/_target", markers: [".rustc_info.json"]),
    folder("/Users/u/Projects/rc/.worktrees/_target/debug", markers: [".cargo-lock"]),
    folder("/Users/u/Projects/rc/.worktrees/_target/release", markers: [".cargo-lock"]),
    folder("/Users/u/Projects/rc/.worktrees/_target/coord", markers: ["CACHEDIR.TAG", ".rustc_info.json"]),   // nested
    folder("/Users/u/Projects/odd/config", markers: [".rustc_info.json"]),                    // no Cargo layout
    folder("/Users/u/Projects/odd2/x", markers: [".rustc_info.json"]),
    folder("/Users/u/Projects/odd2/x/notes", markers: [".cargo-lock"]),                       // only debug or release count
    folder("/Users/u/Projects/app/target", markers: ["CACHEDIR.TAG", ".rustc_info.json"]),
]

@Test func aBuildFolderMadeBeforeCargoRanIsRecognizedByItsLayout() {
    let result = ScanRules.rustBuildFolder.evaluate(RuleContext(scan: Folders(list: layout), home: CanonicalPath("/Users/u")!, now: now))
    #expect(result.candidates.map(\.id.rawValue).sorted() == [
        "rust-build-folder:/Users/u/Projects/app/target",
        "rust-build-folder:/Users/u/Projects/rc/.worktrees/_target",
    ])
}

@Test func theSharedDetectorReturnsOnlyOutermostBuildFolders() {
    #expect(RustBuildFolders.outermost(in: layout).map(\.path.raw) == [
        "/Users/u/Projects/app/target", "/Users/u/Projects/rc/.worktrees/_target",
    ])
}
