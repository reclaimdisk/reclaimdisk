import Inventory
import SharedKernel
import Testing
import TestSupport

private let t0 = Instant(nanosecondsSince1970: 0)
private let dataMount = CanonicalPath("/System/Volumes/Data")!

private func testDisk() -> DiskLayout {
    let data = try! VolumeCapacity(total: ByteCount(1000), available: ByteCount(200), availableIncludingPurgeable: ByteCount(250), usedByVolume: ByteCount(700))
    return DiskLayout(data: data, swapUsed: ByteCount(50))
}

private func draft(_ path: String, takes: UInt64 = 0, frees: UInt64 = 0, aggregate: Kind? = nil, _ children: [NodeDraft] = []) -> NodeDraft {
    let p = CanonicalPath(path)!
    return NodeDraft(name: p.lastComponent, path: p, ownTakesUp: ByteCount(takes), ownFreesAtLeast: ByteCount(frees),
                     newestChange: t0, markers: [], isFile: false, isAggregate: aggregate != nil, aggregateKind: aggregate, children: children)
}

private func scan(_ root: NodeDraft, unique: UInt64 = 0, whole: Bool = false, unreadable: [UnreadableArea] = []) throws -> Scan {
    try Scan(volumeMountPath: dataMount, root: root, disk: testDisk(), startedAt: t0, finishedAt: Instant(nanosecondsSince1970: 1),
             unreadable: unreadable, scannedUniqueBytes: ByteCount(unique), isWholeVolume: whole, classifier: testClassifier)
}

// The hard-link case of spec 8.2: credit lands on an ancestor whose OWN bytes have frees > takesUp,
// but every node TOTAL keeps frees <= takesUp. Scan.init must accept it.
@Test func ownBytesMayCarryFreesWhileTotalsStayValid() throws {
    let child = NodeDraft(name: "B", path: CanonicalPath("/D/B")!, ownTakesUp: ByteCount(4), ownFreesAtLeast: .zero,
                          newestChange: Instant(nanosecondsSince1970: 0), markers: [], isFile: false, isAggregate: false, aggregateKind: nil, children: [])
    let parent = NodeDraft(name: "D", path: CanonicalPath("/D")!, ownTakesUp: .zero, ownFreesAtLeast: ByteCount(4),
                           newestChange: Instant(nanosecondsSince1970: 0), markers: [], isFile: false, isAggregate: false, aggregateKind: nil, children: [child])
    let scan = try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: parent, disk: testDisk(),
                        startedAt: .init(nanosecondsSince1970: 0), finishedAt: .init(nanosecondsSince1970: 1),
                        unreadable: [], scannedUniqueBytes: ByteCount(4), isWholeVolume: false, classifier: testClassifier)
    #expect(scan.root.footprint == (try Footprint(takesUp: ByteCount(4), freesAtLeast: ByteCount(4))))
}

@Test func totalsWithFreesAboveTakesUpAreRejectedNamingThePath() {
    let bad = NodeDraft(name: "X", path: CanonicalPath("/X")!, ownTakesUp: ByteCount(1), ownFreesAtLeast: ByteCount(2),
                        newestChange: Instant(nanosecondsSince1970: 0), markers: [], isFile: false, isAggregate: false, aggregateKind: nil, children: [])
    #expect(throws: InventoryError.freesExceedsTakesUp(CanonicalPath("/X")!)) {
        try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: bad, disk: testDisk(),
                 startedAt: .init(nanosecondsSince1970: 0), finishedAt: .init(nanosecondsSince1970: 1),
                 unreadable: [], scannedUniqueBytes: .zero, isWholeVolume: false, classifier: testClassifier)
    }
}

@Test func kindTotalsSumToRootAndMayHaveFreesAboveTakes() throws {
    // app (projectSource) carries 4 B of hard-link credit; the linked file's takes-up sits in node_modules (buildOutput).
    let root = draft("/Users/u/Projects/app", takes: 0, frees: 4, [
        draft("/Users/u/Projects/app/node_modules", takes: 4, frees: 0),
        draft("/Users/u/Projects/app/src", takes: 10, frees: 10),
    ])
    let s = try scan(root)
    let totals = s.kindTotals()
    #expect(totals[.buildOutput] == KindTotal(takesUp: ByteCount(4), freesAtLeast: .zero))
    #expect(totals[.projectSource] == KindTotal(takesUp: ByteCount(10), freesAtLeast: ByteCount(14)))   // frees > takes, returned as-is
    #expect(totals.values.reduce(ByteCount.zero) { $0 + $1.takesUp } == s.root.footprint.takesUp)
}

@Test func aggregateTakesItsAggregateKind() throws {
    let s = try scan(draft("/Users/u/Projects/app", [draft("/Users/u/Projects/app/.smaller-build-output", takes: 3, frees: 3, aggregate: .buildOutput)]))
    #expect(s.root.kind == .projectSource)
    #expect(s.root.children.first?.kind == .buildOutput)
    #expect(s.root.children.first?.isAggregate == true)
}

@Test func childrenSortBySizeThenName() throws {
    let s = try scan(draft("/D", [draft("/D/b", takes: 5), draft("/D/a", takes: 5), draft("/D/c", takes: 9)]))
    #expect(s.root.children.map(\.name) == ["c", "a", "b"])
}

@Test func notReadableOnlyForWholeVolumeAndClamped() throws {
    #expect(try scan(draft("/D", takes: 1), unique: 650, whole: false).notReadable == nil)
    #expect(try scan(draft("/D", takes: 1), unique: 650, whole: true).notReadable == ByteCount(50))
    #expect(try scan(draft("/D", takes: 1), unique: 800, whole: true).notReadable == .zero)
}

@Test func needsFullDiskAccessOnlyForNotPermittedAreas() throws {
    let denied = UnreadableArea(path: CanonicalPath("/private/var/db/sudo")!, reason: .permissionDenied)
    let locked = UnreadableArea(path: CanonicalPath("/Users/u/Library/Mail")!, reason: .notPermitted)
    #expect(try scan(draft("/D"), unreadable: [denied]).needsFullDiskAccess == false)
    let both = try scan(draft("/D"), unreadable: [locked, denied])
    #expect(both.needsFullDiskAccess == true)
    #expect(both.unreadable.map(\.path.raw) == ["/Users/u/Library/Mail", "/private/var/db/sudo"])   // sorted by path
}

@Test func finishBeforeStartThrows() {
    #expect(throws: InventoryError.finishBeforeStart) {
        try Scan(volumeMountPath: dataMount, root: draft("/D"), disk: testDisk(), startedAt: Instant(nanosecondsSince1970: 5),
                 finishedAt: Instant(nanosecondsSince1970: 4), unreadable: [], scannedUniqueBytes: .zero, isWholeVolume: false, classifier: testClassifier)
    }
}
