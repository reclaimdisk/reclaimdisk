import Catalog
import SharedKernel
import Testing

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private struct FixedCaches: PackageCacheRecords {
    let readings: [PackageCacheReading]
    func read() -> [PackageCacheReading] { readings }
}

/// A package manager can be configured to keep its cache anywhere, even in Documents. A cache inside a personal folder is
/// never offered, whatever the tool says.
@Test func aPackageCacheInsideAPersonalFolderIsNeverOffered() {
    let work = CanonicalPath("/Users/u/Documents/Work")!
    let folder = ScannedFolder(path: work, kind: .personalFiles, takesUp: ByteCount(5_000), freesAtLeast: ByteCount(5_000),
                               newestChange: nil, markers: [], parentMarkers: [])!
    let reading = PackageCacheReading.found(PackageCache(
        tool: "npm", folder: work, clean: ToolCommand(executable: "npm", arguments: ["cache", "clean", "--force"])!,
        clearsWholeFolder: true, busyReason: nil
    ))
    let context = RuleContext(scan: Folders(list: [folder]), home: CanonicalPath("/Users/u")!, now: Instant(nanosecondsSince1970: 0))
    #expect(ToolCacheRules.packageCaches(FixedCaches(readings: [reading])).evaluate(context).candidates.isEmpty)
}
