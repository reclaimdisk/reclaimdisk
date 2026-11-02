import Application
import Catalog
import Inventory
import SharedKernel
import Testing
import TestSupport

private let data = "/System/Volumes/Data"
private let home = CanonicalPath("/Users/u")!

/// A small shared build folder without CACHEDIR.TAG: the scan must keep its debug folder (which holds .cargo-lock) so the
/// rule can see Cargo's layout, even though the folder is far below the size at which folders are kept.
@Test func aSmallSharedBuildFolderWithoutItsTagIsStillListed() async throws {
    let reader = FakeVolumeReader(defaultDeviceID: 1)
    reader.capacity(data, CapacityReading(total: mib(10_000), available: mib(2_000), availableForImportantUsage: mib(2_500), usedByVolume: mib(7_000)))
    reader.directory(data, [Entry.dir("Users")])
    reader.directory("\(data)/Users", [Entry.dir("u")])
    reader.directory("\(data)/Users/u", [Entry.dir("Projects")])
    reader.directory("\(data)/Users/u/Projects", [Entry.dir("rc")])
    reader.directory("\(data)/Users/u/Projects/rc", [Entry.dir(".worktrees")])
    reader.directory("\(data)/Users/u/Projects/rc/.worktrees", [Entry.dir("_target")])
    reader.directory("\(data)/Users/u/Projects/rc/.worktrees/_target", [
        Entry.file(".rustc_info.json", allocated: ByteCount(4_096), fileID: 10), Entry.dir("debug"),
    ])
    reader.directory("\(data)/Users/u/Projects/rc/.worktrees/_target/debug", [
        Entry.file(".cargo-lock", allocated: .zero, fileID: 11), Entry.dir("deps"),
    ])
    reader.directory("\(data)/Users/u/Projects/rc/.worktrees/_target/debug/deps", [Entry.file("librc.rlib", allocated: mib(3), fileID: 12)])
    let scan = try await RunScan(reader: reader, clock: FakeClock(), home: home)(ScanRequest(), progress: { _ in })
    let later = Instant(nanosecondsSince1970: 1_800_000_000_000_000_000)
    let list = await ProposeCandidates(rules: ScanRules.all, clock: FakeClock(start: later), home: home)(scan)
    #expect(list.candidates.map(\.id.rawValue) == ["rust-build-folder:/Users/u/Projects/rc/.worktrees/_target"])
    #expect(list.candidates.first?.estimate.takesUp == ByteCount(4_096) + mib(3))
}
