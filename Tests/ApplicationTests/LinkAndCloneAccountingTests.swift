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

/// Default folding (256 MiB): nothing in these trees is big enough to keep, so everything folds into /D's aggregates.
private func folding() -> ScanOptions { ScanOptions(root: CanonicalPath("/D")!, classifier: testClassifier) }

private func validated(_ result: ScanBuildResult) throws -> Scan {
    let capacity = try VolumeCapacity(total: mib(100), available: mib(50), availableIncludingPurgeable: mib(50), usedByVolume: mib(40))
    return try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: result.root, disk: DiskLayout(data: capacity, swapUsed: nil),
                    startedAt: result.startedAt, finishedAt: result.finishedAt, unreadable: result.unreadable,
                    scannedUniqueBytes: result.scannedUniqueBytes, isWholeVolume: false, classifier: testClassifier)
}

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
    let scan = try validated(result)
    #expect(scan.root.footprint.freesAtLeast <= scan.root.footprint.takesUp)
}

/// /D/proj/a/x and /D/proj/a/node_modules/x are one inode. Both folders fold, into different kinds (other, build output),
/// so no aggregate holds both links: the credit goes to /D, the smallest node that does (spec 8.3).
@Test func hardLinkSplitAcrossFoldedKindsCreditsTheKeptFolder() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/D", [Entry.dir("proj")])
    reader.directory("/D/proj", [Entry.dir("a")])
    reader.directory("/D/proj/a", [Entry.file("x", allocated: mib(1), fileID: 7, links: 2), Entry.dir("node_modules")])
    reader.directory("/D/proj/a/node_modules", [Entry.file("x", allocated: mib(1), fileID: 7, links: 2)])
    let result = try await ScanBuilder(reader: reader, clock: FakeClock()).build(folding(), progress: { _ in })
    let d = result.root
    #expect(d.ownFreesAtLeast == mib(1))
    #expect(d.children.map(\.aggregateKind) == [.buildOutput])                // "other" keeps no bytes, so it gets no aggregate
    #expect(d.children.first?.ownTakesUp == mib(1) && d.children.first?.ownFreesAtLeast == .zero)
    let scan = try validated(result)                                          // threw freesExceedsTakesUp(/D/.smaller-other) before
    #expect(scan.root.footprint.takesUp == mib(1) && scan.root.footprint.freesAtLeast == mib(1))
}

/// Both links sit inside one folded node_modules, so its aggregate holds them all and keeps the credit.
@Test func hardLinkInsideOneFoldedKindCreditsThatAggregate() async throws {
    let reader = FakeVolumeReader()
    reader.directory("/D", [Entry.dir("proj")])
    reader.directory("/D/proj", [Entry.dir("node_modules")])
    reader.directory("/D/proj/node_modules", [Entry.dir("p"), Entry.dir("q")])
    reader.directory("/D/proj/node_modules/p", [Entry.file("x", allocated: mib(1), fileID: 7, links: 2)])
    reader.directory("/D/proj/node_modules/q", [Entry.file("x", allocated: mib(1), fileID: 7, links: 2)])
    let result = try await ScanBuilder(reader: reader, clock: FakeClock()).build(folding(), progress: { _ in })
    let modules = try #require(result.root.children.first { $0.aggregateKind == .buildOutput })
    #expect(modules.ownTakesUp == mib(1) && modules.ownFreesAtLeast == mib(1))
    #expect(result.root.ownFreesAtLeast == .zero)
    _ = try validated(result)
}

/// Random small trees with hard links between folders of mixed kinds, kept or folded at random thresholds:
/// Scan validation never fails, and the root frees exactly the unlinked files' private bytes plus every fully found link.
@Test(arguments: 0..<500) func hardLinksNeverBreakScanValidation(seed: Int) async throws {
    var rng = SeededRandom(seed: UInt64(seed))
    let names = ["node_modules", "target", "Caches", "src", "docs", "a", "b"]
    var folders = ["/D"]
    var entries: [String: [DirectoryEntry]] = ["/D": []]
    for _ in 0..<Int.random(in: 1...12, using: &rng) {
        let parent = folders.randomElement(using: &rng)!, name = names.randomElement(using: &rng)!
        let path = "\(parent)/\(name)"
        guard entries[path] == nil else { continue }
        entries[parent, default: []].append(Entry.dir(name))
        entries[path] = []
        folders.append(path)
    }
    var nextID: UInt64 = 1, expectedFrees: UInt64 = 0
    for folder in folders where Int.random(in: 0..<4, using: &rng) == 0 {   // few unlinked files, so aggregates have little slack
        let allocated = mib(UInt64.random(in: 1...4, using: &rng))
        let privateSize = ByteCount(UInt64.random(in: 0...allocated.bytes, using: &rng))
        entries[folder, default: []].append(Entry.file("f\(nextID)", allocated: allocated, private: privateSize, fileID: nextID))
        expectedFrees += privateSize.bytes
        nextID += 1
    }
    if Bool.random(using: &rng) { entries[folders.randomElement(using: &rng)!, default: []].append(Entry.file("CACHEDIR.TAG", allocated: .zero, fileID: 999)) }
    for _ in 0..<Int.random(in: 1...3, using: &rng) {
        let linkFolders = (0..<Int.random(in: 2...3, using: &rng)).map { _ in folders.randomElement(using: &rng)! }
        let oneOutside = Int.random(in: 0..<4, using: &rng) == 0
        let allocated = mib(UInt64.random(in: 1...4, using: &rng))
        for (n, folder) in linkFolders.enumerated() {
            entries[folder, default: []].append(Entry.file("l\(nextID)-\(n)", allocated: allocated, fileID: nextID, links: UInt32(linkFolders.count + (oneOutside ? 1 : 0))))
        }
        if !oneOutside { expectedFrees += allocated.bytes }
        nextID += 1
    }
    let reader = FakeVolumeReader()
    for (path, list) in entries { reader.directory(path, list) }
    let threshold = [ByteCount.zero, mib(3), ByteCount(268_435_456)].randomElement(using: &rng)!
    let options = ScanOptions(root: CanonicalPath("/D")!, classifier: testClassifier, minimumNodeSize: threshold)
    let result = try await ScanBuilder(reader: reader, clock: FakeClock()).build(options, progress: { _ in })
    let scan = try validated(result)
    #expect(scan.root.footprint.freesAtLeast == ByteCount(expectedFrees))
}
