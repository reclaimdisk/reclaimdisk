import AppFeature
import Inventory
import SharedKernel
import Testing
import TestSupport

private let t0 = Instant(nanosecondsSince1970: 0)

private func leaf(_ path: String, _ bytes: UInt64) -> NodeDraft {
    let p = CanonicalPath(path)!
    return NodeDraft(name: p.lastComponent, path: p, ownTakesUp: ByteCount(bytes), ownFreesAtLeast: .zero, newestChange: t0,
                     markers: [], isFile: false, isAggregate: false, aggregateKind: nil, children: [])
}

private func wholeVolumeScan(unique: UInt64, whole: Bool = true) throws -> Scan {
    let root = NodeDraft(name: "Data volume", path: .root, ownTakesUp: .zero, ownFreesAtLeast: .zero, newestChange: t0, markers: [],
                         isFile: false, isAggregate: false, aggregateKind: nil,
                         children: [leaf("/Users/u/Projects", 333), leaf("/Users/u/Library/Caches", 777), leaf("/Applications", 111)])
    let data = try VolumeCapacity(total: ByteCount(10_007), available: ByteCount(2_003), availableIncludingPurgeable: ByteCount(2_003), usedByVolume: ByteCount(5_001))
    return try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: root, disk: DiskLayout(data: data, swapUsed: ByteCount(997)),
                    startedAt: t0, finishedAt: t0, unreadable: [], scannedUniqueBytes: ByteCount(unique), isWholeVolume: whole, classifier: testClassifier)
}

@Test func wholeVolumeSegmentsSumToTheDiskExactly() throws {
    let segments = DiskBarModel.segments(for: try wholeVolumeScan(unique: 1_000))   // kinds sum to 1,221 but only 1,000 are unique
    #expect(segments.reduce(0) { $0 + $1.bytes.bytes } == 10_007)
    #expect(segments.map(\.part) == [.kind(.caches), .kind(.projectSource), .kind(.apps), .kind(.notReadable), .swap, .otherVolumes, .free])
    #expect(segments.prefix(3).reduce(0) { $0 + $1.bytes.bytes } == 1_000)              // kinds scaled into the unique bytes
    #expect(segments[3].bytes == ByteCount(4_001))                                       // not readable: 5,001 − 1,000
    #expect(segments[4].bytes == ByteCount(997) && segments[5].bytes == ByteCount(2_006) && segments[6].bytes == ByteCount(2_003))
}

@Test func subtreeSegmentsAreUnscaledKindsOnly() throws {
    let segments = DiskBarModel.segments(for: try wholeVolumeScan(unique: 1_000, whole: false))
    #expect(segments.map(\.part) == [.kind(.caches), .kind(.projectSource), .kind(.apps)])
    #expect(segments.map(\.bytes.bytes) == [777, 333, 111])
}

@Test func keyShowsRealTakesUpWhileTheBarIsScaled() throws {
    let segments = DiskBarModel.segments(for: try wholeVolumeScan(unique: 1_000))
    #expect(segments.prefix(3).map(\.shownBytes.bytes) == [777, 333, 111])          // the CLI's takes-up
    #expect(segments.prefix(3).reduce(0) { $0 + $1.bytes.bytes } == 1_000)          // the bar still fits the volume
    #expect(segments.dropFirst(3).allSatisfy { $0.shownBytes == $0.bytes })
}
