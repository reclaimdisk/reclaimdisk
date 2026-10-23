import Application
import Inventory
import SharedKernel
import Testing
import TestSupport

private let data = "/System/Volumes/Data"

private func volume(swap: Bool = true) -> FakeVolumeReader {
    let reader = FakeVolumeReader(defaultDeviceID: 1)
    reader.capacity(data, CapacityReading(total: mib(1000), available: mib(200), availableForImportantUsage: mib(250), usedByVolume: mib(700)))
    if swap { reader.capacity("/System/Volumes/VM", CapacityReading(total: mib(1000), available: mib(200), availableForImportantUsage: mib(200), usedByVolume: mib(50))) }
    reader.directory(data, [Entry.dir("Users")])
    reader.directory("\(data)/Users", [Entry.file("f", allocated: mib(600), fileID: 1)])
    return reader
}

private func runScan(_ reader: FakeVolumeReader) -> RunScan { RunScan(reader: reader, clock: FakeClock(), home: CanonicalPath("/Users/u")!) }

@Test func wholeVolumeScanReportsNotReadable() async throws {
    let scan = try await runScan(volume())(ScanRequest(), progress: { _ in })
    #expect(scan.isWholeVolume)
    #expect(scan.root.path == .root && scan.root.name == "Data volume")
    #expect(scan.scannedUniqueBytes == mib(600))
    #expect(scan.notReadable == mib(100))                 // used 700 − scanned 600
    #expect(scan.disk.swapUsed == mib(50))
    #expect(scan.volumeMountPath.raw == data)
}

@Test func missingSwapStillScans() async throws {
    let scan = try await runScan(volume(swap: false))(ScanRequest(), progress: { _ in })
    #expect(scan.disk.swapUsed == nil)
}

@Test func badPathsFailBeforeAnyRead() async {
    let reader = volume()
    reader.entryType("/Users/u/file.txt", .file)
    reader.entryType("/Users/u/link", .symlink)
    let cases: [(String, ScanError)] = [
        ("/Users/u/file.txt", .notADirectory(CanonicalPath("/Users/u/file.txt")!)),
        ("/Users/u/link", .notADirectory(CanonicalPath("/Users/u/link")!)),
        ("/Users/u/missing", .unreadable(CanonicalPath("/Users/u/missing")!, .notFound)),
    ]
    for (raw, expected) in cases {
        await #expect(throws: expected) { try await runScan(reader)(ScanRequest(path: CanonicalPath(raw)!), progress: { _ in }) }
    }
    #expect(reader.readLog.isEmpty)
}

@Test func pathOnAnotherVolumeIsRejected() async {
    let reader = volume()
    reader.directory("/Volumes/USB", [])
    reader.mount("/Volumes/USB", "/Volumes/USB")
    await #expect(throws: ScanError.notOnDataVolume(CanonicalPath("/Volumes/USB")!)) {
        try await runScan(reader)(ScanRequest(path: CanonicalPath("/Volumes/USB")!), progress: { _ in })
    }
}

@Test func subtreeScanUsesTheFolderAsRoot() async throws {
    let reader = volume()
    reader.directory("/Users/u/Projects", [Entry.file("a", allocated: mib(1), fileID: 1)])
    let scan = try await runScan(reader)(ScanRequest(path: CanonicalPath("/Users/u/Projects")!), progress: { _ in })
    #expect(!scan.isWholeVolume && scan.notReadable == nil)
    #expect(scan.root.name == "Projects" && scan.root.kind == .projectSource)
}

@Test func unreadableFolderMapsToScanError() async {
    let reader = volume()
    reader.failing("/Users/u/Library/Mail", .notPermitted)
    await #expect(throws: ScanError.unreadable(CanonicalPath("/Users/u/Library/Mail")!, .notPermitted)) {
        try await runScan(reader)(ScanRequest(path: CanonicalPath("/Users/u/Library/Mail")!), progress: { _ in })
    }
}

@Test func preflightMatchesTheScanAndReadsNothing() async throws {
    let reader = volume()
    let layout = try runScan(reader).preflight()
    #expect(reader.readLog.isEmpty)
    let scan = try await runScan(reader)(ScanRequest(), progress: { _ in })
    #expect(scan.disk == layout)
    #expect(layout.data.availableIncludingPurgeable == mib(250))
}

@Test func unreadableDataVolumeCapacityThrows() {
    let reader = volume()
    reader.failingCapacity(data, .permissionDenied)
    #expect(throws: ScanError.unreadable(CanonicalPath(data)!, .permissionDenied)) { try runScan(reader).preflight() }
}

// Final review, Important 3: System and Data share a device id, so the volume is decided by mount point.
@Test func systemVolumePathsAreRejected() async {
    let reader = volume()
    reader.directory("/System/Library", [])
    reader.mount("/System", "/")
    reader.directory("/", [])
    reader.mount("/", "/")
    for raw in ["/System/Library", "/"] {
        await #expect(throws: ScanError.notOnDataVolume(CanonicalPath(raw)!)) {
            try await runScan(reader)(ScanRequest(path: CanonicalPath(raw)!), progress: { _ in })
        }
    }
    #expect(reader.readLog.isEmpty)
}
