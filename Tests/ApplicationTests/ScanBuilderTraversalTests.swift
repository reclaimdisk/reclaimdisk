import Application
import Foundation
import Inventory
import SharedKernel
import Testing
import TestSupport

private let big = ByteCount.gibibyte

private func build(_ reader: FakeVolumeReader, _ options: ScanOptions) async throws -> ScanBuildResult {
    try await ScanBuilder(reader: reader, clock: FakeClock()).build(options, progress: { _ in })
}

@Test func ownBytesAndNestedTotals() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.file("f", allocated: mib(1), fileID: 1), Entry.dir("A")])
    reader.directory("/S/A", [Entry.file("g", allocated: mib(2), private: mib(1), fileID: 2), Entry.dir("B")])
    reader.directory("/S/A/B", [Entry.file("h", allocated: mib(3), fileID: 3)])
    let result = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier,
                                                     minimumNodeSize: big, retainedDirectoryNames: ["A", "B"]))
    let root = result.root, a = root.child("A"), b = a.child("B")
    #expect(root.ownTakesUp == mib(1) && root.ownFreesAtLeast == mib(1))
    #expect(a.ownTakesUp == mib(2) && a.ownFreesAtLeast == mib(1))
    #expect(b.ownTakesUp == mib(3))
    #expect(root.totalTakesUp == mib(6) && root.totalFreesAtLeast == mib(5))
    #expect(result.scannedUniqueBytes == mib(6))
}

@Test func largeFileBecomesItsOwnNode() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.file("big.raw", allocated: big, fileID: 1), Entry.file("small", allocated: mib(1), fileID: 2)])
    let root = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier)).root
    let file = root.child("big.raw")
    #expect(file.isFile && file.ownTakesUp == big && file.path.raw == "/S/big.raw")
    #expect(root.ownTakesUp == mib(1))
}

@Test func mountPointsOtherDevicesAndSymlinksAreNeverRead() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.dir("mnt", mountPoint: true), Entry.dir("ext", device: 9), Entry.symlink("link"), Entry.dir("ok")])
    reader.directory("/S/ok", [])
    reader.directory("/S/mnt", [])
    reader.directory("/S/ext", [])
    _ = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier))
    #expect(reader.readLog.map(\.raw).sorted() == ["/S", "/S/ok"])
}

@Test func unreadableFoldersAreRecordedOneByOne() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/System/Volumes/Data", [Entry.dir("Users")])
    reader.directory("/System/Volumes/Data/Users", [Entry.dir("u")])
    reader.directory("/System/Volumes/Data/Users/u", [Entry.dir("Library")])
    reader.directory("/System/Volumes/Data/Users/u/Library", [Entry.dir("Mail"), Entry.dir("Safari"), Entry.dir("Deep")])
    reader.failing("/System/Volumes/Data/Users/u/Library/Mail", .permissionDenied)
    reader.failing("/System/Volumes/Data/Users/u/Library/Safari", .notPermitted)
    reader.failing("/System/Volumes/Data/Users/u/Library/Deep", .nameTooLong)
    let result = try await build(reader, ScanOptions(root: CanonicalPath("/System/Volumes/Data")!, classifier: testClassifier))
    #expect(result.unreadable == [
        UnreadableArea(path: CanonicalPath("/Users/u/Library/Deep")!, reason: .pathTooLong),
        UnreadableArea(path: CanonicalPath("/Users/u/Library/Mail")!, reason: .permissionDenied),
        UnreadableArea(path: CanonicalPath("/Users/u/Library/Safari")!, reason: .notPermitted),
    ])
}

@Test func vanishedFoldersAreSkippedSilently() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.dir("gone"), Entry.dir("stays"), Entry.file("f", allocated: mib(1), fileID: 1)])
    reader.failing("/S/gone", .notFound)
    reader.directory("/S/stays", [])
    let result = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier))
    #expect(result.unreadable.isEmpty)
    #expect(result.root.totalTakesUp == mib(1))
}

@Test func rootReadErrorThrows() async {
    let reader = FakeVolumeReader()
    reader.failing("/S", .permissionDenied)
    await #expect(throws: ScanBuildError.rootUnreadable(.permissionDenied)) {
        try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier))
    }
}

@Test func rootIsNamedDataVolumeOnlyForTheWholeVolume() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/System/Volumes/Data", [])
    reader.directory("/Users/u/Projects", [])
    let whole = try await build(reader, ScanOptions(root: CanonicalPath("/System/Volumes/Data")!, classifier: testClassifier)).root
    #expect(whole.name == "Data volume" && whole.path == .root)
    let subtree = try await build(reader, ScanOptions(root: CanonicalPath("/Users/u/Projects")!, classifier: testClassifier)).root
    #expect(subtree.name == "Projects" && subtree.path.raw == "/Users/u/Projects")
}

@Test func resultIsIndependentOfEntryOrder() async throws {
    func tree() -> FakeVolumeReader {
        let reader = FakeVolumeReader()
        reader.directory("/S", (0..<6).map { Entry.dir("d\($0)") } + [Entry.file("f", allocated: mib(1), fileID: 1)])
        for i in 0..<6 { reader.directory("/S/d\(i)", [Entry.file("x", allocated: mib(UInt64(i + 1)), fileID: UInt64(10 + i)), Entry.dir("in")])
                         reader.directory("/S/d\(i)/in", [Entry.file("y", allocated: mib(1), fileID: UInt64(20 + i))]) }
        return reader
    }
    let options = ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier, minimumNodeSize: mib(3), maxConcurrentReads: 4)
    let forward = try await build(tree(), options)
    let reversedReader = tree(); reversedReader.reverseEntryOrder = true
    let backward = try await build(reversedReader, options)
    #expect(forward == backward)
}

@Test func progressEndsWithTheFullCount() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.dir("a"), Entry.dir("b")])
    reader.directory("/S/a", [])
    reader.directory("/S/b", [])
    let last = LastValue<ScanProgress>()
    _ = try await ScanBuilder(reader: reader, clock: FakeClock()).build(ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier)) { last.set($0) }
    #expect(last.get()?.directoriesRead == 3)
}

@Test func cancellationStopsFurtherReads() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", (0..<10).map { Entry.dir("d\($0)") })
    for i in 0..<10 {
        reader.directory("/S/d\(i)", (0..<10).map { Entry.dir("e\($0)") })
        for j in 0..<10 { reader.directory("/S/d\(i)/e\(j)", []) }
    }
    let box = TaskBox()
    reader.onRead = { _, readsSoFar in if readsSoFar == 3 { box.cancelWhenSet() } }
    let options = ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier, maxConcurrentReads: 2)
    let task = Task { try await ScanBuilder(reader: reader, clock: FakeClock()).build(options, progress: { _ in }) }
    box.set(task)
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(reader.readLog.count <= 3 + 2)
}

/// Holds the task under test so a read hook on another thread can cancel it.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<ScanBuildResult, any Error>?
    func set(_ task: Task<ScanBuildResult, any Error>) { lock.withLock { self.task = task } }
    func cancelWhenSet() {
        for _ in 0..<10_000 {
            if let task = lock.withLock({ self.task }) { task.cancel(); return }
            usleep(100)
        }
    }
}

private final class LastValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.withLock { value = v } }
    func get() -> T? { lock.withLock { value } }
}

@Test func cloudOnlyFoldersAreSkippedSilently() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.dir("cloud"), Entry.file("f", allocated: mib(1), fileID: 1)])
    reader.failing("/S/cloud", .cloudOnly)
    let result = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier))
    #expect(result.unreadable.isEmpty)
    #expect(result.root.totalTakesUp == mib(1))
}

/// APFS clamps dates before 1677 to Int64.min nanoseconds, the table's "no date" value.
@Test func largeFileWithAClampedDateHasNoNewestChange() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [Entry.file("old.raw", allocated: big, fileID: 1, modified: Instant(nanosecondsSince1970: Int64.min))])
    let root = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier)).root
    #expect(root.child("old.raw").newestChange == nil)
    #expect(root.newestChange == nil)
}

@Test func emptyFolderHasNoNewestChange() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/S", [])
    let root = try await build(reader, ScanOptions(root: CanonicalPath("/S")!, classifier: testClassifier)).root
    #expect(root.newestChange == nil)
}
