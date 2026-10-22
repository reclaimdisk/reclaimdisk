import Application
import Inventory
import SharedKernel
import Testing
import TestSupport

/// /D/A/x and /D/B/y are one inode (fileID 7); /D/C holds three full clones (cloneID 9).
private func fixtureWithHardLinkAndClones(linkCount: UInt32) -> FakeVolumeReader {
    let reader = FakeVolumeReader()
    reader.directory("/D", [Entry.dir("A"), Entry.dir("B"), Entry.dir("C")])
    reader.directory("/D/A", [Entry.file("x", allocated: mib(4), private: mib(4), fileID: 7, links: linkCount)])
    reader.directory("/D/B", [Entry.file("y", allocated: mib(4), private: mib(4), fileID: 7, links: linkCount)])
    reader.directory("/D/C", (1...3).map { Entry.file("c\($0)", allocated: mib(4), private: .zero, fileID: UInt64(20 + $0), cloneID: 9, refCount: 3) })
    return reader
}

private func options(_ root: String = "/D") -> ScanOptions { ScanOptions(root: CanonicalPath(root)!, classifier: testClassifier, minimumNodeSize: .zero) }

@Test func hardLinkCreditGoesToCommonAncestorWhenAllLinksAreInside() async throws {
    let result = try await ScanBuilder(reader: fixtureWithHardLinkAndClones(linkCount: 2), clock: FakeClock()).build(options(), progress: { _ in })
    let d = result.root, a = d.child("A"), b = d.child("B")
    #expect(a.totalTakesUp == mib(4) && a.totalFreesAtLeast == .zero)      // first canonical path "/D/A/x"
    #expect(b.totalTakesUp == .zero && b.totalFreesAtLeast == .zero)
    #expect(d.ownFreesAtLeast == mib(4))                                   // LCA of /D/A and /D/B is /D
    #expect(d.totalTakesUp == mib(4) + mib(12))                            // hard link once + three clones
}

@Test func hardLinkWithALinkOutsideTheScanFreesNothing() async throws {
    let result = try await ScanBuilder(reader: fixtureWithHardLinkAndClones(linkCount: 3), clock: FakeClock()).build(options(), progress: { _ in })
    #expect(result.root.totalFreesAtLeast == .zero)                        // clones are private 0; link 3 is unseen
}

@Test func fullCloneGroupCountsOnceInScannedUniqueBytes() async throws {
    let result = try await ScanBuilder(reader: fixtureWithHardLinkAndClones(linkCount: 2), clock: FakeClock()).build(options(), progress: { _ in })
    #expect(result.scannedUniqueBytes == mib(4) + mib(4))                  // hard link once + clone group once
}

@Test func linkPairInsideOneFolderCreditsThatFolder() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/E", [Entry.dir("F")])
    reader.directory("/E/F", [Entry.file("p", allocated: mib(4), fileID: 5, links: 2), Entry.file("q", allocated: mib(4), fileID: 5, links: 2)])
    let e = try await ScanBuilder(reader: reader, clock: FakeClock()).build(options("/E"), progress: { _ in }).root
    #expect(e.child("F").ownTakesUp == mib(4) && e.child("F").ownFreesAtLeast == mib(4))
    #expect(e.ownFreesAtLeast == .zero)
}

@Test func accountingIsIndependentOfEntryOrder() async throws {
    let forward = try await ScanBuilder(reader: fixtureWithHardLinkAndClones(linkCount: 2), clock: FakeClock()).build(options(), progress: { _ in })
    let reversedReader = fixtureWithHardLinkAndClones(linkCount: 2)
    reversedReader.reverseEntryOrder = true
    let backward = try await ScanBuilder(reader: reversedReader, clock: FakeClock()).build(options(), progress: { _ in })
    #expect(forward == backward)
}

@Test func resultPassesScanValidation() async throws {
    let result = try await ScanBuilder(reader: fixtureWithHardLinkAndClones(linkCount: 2), clock: FakeClock()).build(options(), progress: { _ in })
    let capacity = try VolumeCapacity(total: mib(100), available: mib(50), availableIncludingPurgeable: mib(50), usedByVolume: mib(40))
    let scan = try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: result.root, disk: DiskLayout(data: capacity, swapUsed: nil),
                        startedAt: result.startedAt, finishedAt: result.finishedAt, unreadable: result.unreadable,
                        scannedUniqueBytes: result.scannedUniqueBytes, isWholeVolume: false, classifier: testClassifier)
    #expect(scan.root.footprint.freesAtLeast <= scan.root.footprint.takesUp)
}
