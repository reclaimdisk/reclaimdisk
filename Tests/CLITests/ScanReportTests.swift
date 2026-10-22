import Foundation
import Inventory
import SharedKernel
import Testing
import TestSupport
@testable import CLI

private let t0 = Instant(seconds: 1_761_000_000, nanoseconds: 123_000_000)

private func makeScan(whole: Bool, unreadable: [UnreadableArea] = [], childName: String = "app") throws -> Scan {
    let child = NodeDraft(name: childName, path: CanonicalPath("/Users/u/Projects/\(childName)")!, ownTakesUp: mib(3), ownFreesAtLeast: mib(2),
                          newestChange: t0, markers: ["CACHEDIR.TAG"], isFile: false, isAggregate: false, aggregateKind: nil, children: [])
    let root = NodeDraft(name: "Projects", path: CanonicalPath("/Users/u/Projects")!, ownTakesUp: mib(1), ownFreesAtLeast: mib(1),
                         newestChange: t0, markers: [], isFile: false, isAggregate: false, aggregateKind: nil, children: [child])
    let data = try VolumeCapacity(total: mib(1000), available: mib(200), availableIncludingPurgeable: mib(250), usedByVolume: mib(700))
    return try Scan(volumeMountPath: CanonicalPath("/System/Volumes/Data")!, root: root, disk: DiskLayout(data: data, swapUsed: nil),
                    startedAt: t0, finishedAt: t0, unreadable: unreadable, scannedUniqueBytes: mib(4), isWholeVolume: whole, classifier: testClassifier)
}

private func decode(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Test func jsonHasEveryContractKey() throws {
    let json = try decode(try ScanReport.json(makeScan(whole: false)))
    #expect(Set(json.keys) == ["schemaVersion", "scope", "volume", "startedAt", "finishedAt", "disk", "scannedUniqueBytes",
                               "notReadableBytes", "needsFullDiskAccess", "unreadableAreas", "kinds", "root"])
    #expect(json["schemaVersion"] as? Int == 1)
    #expect(json["scope"] as? String == "subtree")
    #expect(json["startedAt"] as? String == "2025-10-20T22:40:00.123Z")
    #expect(json["notReadableBytes"] is NSNull)
    let disk = try #require(json["disk"] as? [String: Any])
    #expect(Set(disk.keys) == ["total", "available", "availableIncludingPurgeable", "dataUsed", "swapUsed", "otherVolumesUsed"])
    #expect(disk["swapUsed"] is NSNull)
    let root = try #require(json["root"] as? [String: Any])
    #expect(Set(root.keys) == ["name", "path", "kind", "takesUp", "freesAtLeast", "newestChange", "isFile", "isAggregate", "markers", "children"])
    #expect(root["takesUp"] as? Int == 4 * 1_048_576)
    let child = try #require((root["children"] as? [[String: Any]])?.first)
    #expect(child["markers"] as? [String] == ["CACHEDIR.TAG"])
    let kinds = try #require(json["kinds"] as? [[String: Any]])
    #expect(kinds.first?["kind"] as? String == "project-source")
}

@Test func oddNamesStayValidJSONAndAreEscapedInText() throws {
    let scan = try makeScan(whole: false, childName: "line\nbreak")
    let child = try #require(((try decode(try ScanReport.json(scan)))["root"] as? [String: Any])?["children"] as? [[String: Any]])
    #expect(child.first?["name"] as? String == "line\nbreak")
    let text = ScanReport.text(scan)
    #expect(text.contains("line\\nbreak"))
    #expect(!text.contains("line\nbreak"))
}

@Test func notCountedAndFullDiskAccessLinesFollowTheScan() throws {
    #expect(!ScanReport.text(try makeScan(whole: false)).contains("Not counted"))
    let whole = ScanReport.text(try makeScan(whole: true))
    #expect(whole.contains("Not counted: 696 MiB (system-only folders, file-system metadata and snapshots)"))
    #expect(!whole.contains("Full Disk Access"))
    let locked = try makeScan(whole: true, unreadable: [UnreadableArea(path: CanonicalPath("/Users/u/Library/Mail")!, reason: .notPermitted)])
    #expect(ScanReport.text(locked).contains("Some folders need Full Disk Access: open System Settings › Privacy & Security › Full Disk Access to include them."))
    #expect(whole.contains("Free: 200 MiB of 1000 MiB"))
    #expect(whole.contains("Project source"))
}

@Test func pathArgumentsResolveOrFailWithAUsageMessage() throws {
    let cwd = CanonicalPath("/private/tmp")!
    #expect(try ScanCommand.resolvePath("/tmp", currentDirectory: cwd) == CanonicalPath("/private/tmp")!)
    #expect(throws: CLIFailure.self) { try ScanCommand.resolvePath("/", currentDirectory: cwd) }
    #expect(throws: CLIFailure.self) { try ScanCommand.resolvePath("/private/tmp/reclaimdisk-missing-\(UUID().uuidString)", currentDirectory: cwd) }
}
