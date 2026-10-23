import Inventory
import SharedKernel
import TestSupport

/// /R (own 10): A { A1 (own 30) { x 20, y 10 }, A2 40 }, B 100, Z 0, .smaller-other aggregate 5, real ".smaller-other" 3.
func mapTestTree() throws -> Node {
    func d(_ path: String, own: UInt64, aggregate: Bool = false, _ children: [NodeDraft] = []) -> NodeDraft {
        let p = CanonicalPath(path)!
        return NodeDraft(name: aggregate ? "1 smaller folder" : p.lastComponent, path: p, ownTakesUp: ByteCount(own), ownFreesAtLeast: .zero,
                         newestChange: Instant(nanosecondsSince1970: 0), markers: [], isFile: false, isAggregate: aggregate,
                         aggregateKind: aggregate ? .other : nil, children: children)
    }
    let root = d("/R", own: 10, [
        d("/R/A", own: 0, [d("/R/A/A1", own: 30, [d("/R/A/A1/x", own: 20), d("/R/A/A1/y", own: 10)]), d("/R/A/A2", own: 40)]),
        d("/R/B", own: 100),
        d("/R/Z", own: 0),
        d("/R/.smaller-other", own: 5, aggregate: true),
        d("/R/.smaller-other", own: 3),
    ])
    let data = try VolumeCapacity(total: ByteCount(1_000), available: ByteCount(500), availableIncludingPurgeable: ByteCount(500), usedByVolume: ByteCount(400))
    return try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: root, disk: DiskLayout(data: data, swapUsed: nil),
                    startedAt: Instant(nanosecondsSince1970: 0), finishedAt: Instant(nanosecondsSince1970: 0), unreadable: [],
                    scannedUniqueBytes: ByteCount(218), isWholeVolume: false, classifier: testClassifier).root
}

extension Node {
    func find(_ path: String) -> Node? {
        if self.path.raw == path, !isAggregate { return self }
        for child in children { if let match = child.find(path) { return match } }
        return nil
    }
}
