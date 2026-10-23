import AppFeature
import Inventory
import SharedKernel
import Testing
import TestSupport

@Test func ownLockedFoldersComeFirst() throws {
    let locked = ["/.DocumentRevisions-V100", "/.Spotlight-V100", "/Library/Bluetooth", "/Library/Trial", "/Users/u/.Trash", "/Users/u/Library/Mail"]
        .map { UnreadableArea(path: CanonicalPath($0)!, reason: .notPermitted) }
    let denied = UnreadableArea(path: CanonicalPath("/Users/u/Projects/x")!, reason: .permissionDenied)
    let root = NodeDraft(name: "Data volume", path: .root, ownTakesUp: .zero, ownFreesAtLeast: .zero, newestChange: nil, markers: [],
                         isFile: false, isAggregate: false, aggregateKind: nil, children: [])
    let data = try VolumeCapacity(total: mib(100), available: mib(50), availableIncludingPurgeable: mib(50), usedByVolume: mib(40))
    let scan = try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: root, disk: DiskLayout(data: data, swapUsed: nil),
                        startedAt: Instant(nanosecondsSince1970: 0), finishedAt: Instant(nanosecondsSince1970: 0), unreadable: locked + [denied],
                        scannedUniqueBytes: .zero, isWholeVolume: true, classifier: testClassifier)
    #expect(LockedFolders.examples(in: scan, home: CanonicalPath("/Users/u")!).map(\.raw)
            == ["/Users/u/.Trash", "/Users/u/Library/Mail", "/.DocumentRevisions-V100", "/.Spotlight-V100", "/Library/Bluetooth"])
}
