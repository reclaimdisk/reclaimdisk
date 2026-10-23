import Application
import Inventory
import SharedKernel
import Testing
import TestSupport

private let app = "/Users/u/Projects/app"

private func projectTree(withNodeModules: Bool) -> FakeVolumeReader {
    let reader = FakeVolumeReader()
    var entries = [Entry.file("data.bin", allocated: ByteCount.gibibyte + ByteCount.gibibyte, fileID: 1)]
    entries += (0..<5).map { Entry.dir("small\($0)") }
    if withNodeModules { entries.append(Entry.dir("node_modules")) }
    entries.append(Entry.dir("outer"))
    reader.directory(app, entries)
    for i in 0..<5 { reader.directory("\(app)/small\(i)", [Entry.file("f", allocated: mib(1), fileID: UInt64(10 + i))]) }
    reader.directory("\(app)/node_modules", [Entry.file("pkg.js", allocated: mib(1), fileID: 30)])
    reader.directory("\(app)/outer", [Entry.dir("inner")])
    reader.directory("\(app)/outer/inner", [Entry.file("CACHEDIR.TAG", allocated: .zero, fileID: 40), Entry.file("x", allocated: mib(1), fileID: 41)])
    return reader
}

private func build(_ reader: FakeVolumeReader) async throws -> NodeDraft {
    try await ScanBuilder(reader: reader, clock: FakeClock())
        .build(ScanOptions(root: CanonicalPath(app)!, classifier: testClassifier), progress: { _ in }).root
}

@Test func smallFoldersFoldIntoOneAggregatePerKind() async throws {
    let root = try await build(projectTree(withNodeModules: false))
    let aggregate = root.child("5 smaller folders")
    #expect(aggregate.isAggregate && aggregate.aggregateKind == .projectSource)
    #expect(aggregate.ownTakesUp == mib(5))
    #expect(aggregate.path.raw == "\(app)/.smaller-project-source")
}

@Test func foldedBuildOutputKeepsItsOwnKind() async throws {
    let root = try await build(projectTree(withNodeModules: true))
    #expect(root.child("5 smaller folders").aggregateKind == .projectSource)
    let modules = root.child("1 smaller folder")
    #expect(modules.aggregateKind == .buildOutput && modules.ownTakesUp == mib(1))
    #expect(modules.path.raw == "\(app)/.smaller-build-output")
}

@Test func markerFolderAndItsAncestorsAreKept() async throws {
    let root = try await build(projectTree(withNodeModules: false))
    let inner = root.child("outer").child("inner")
    #expect(inner.markers == ["CACHEDIR.TAG"])
    #expect(inner.ownTakesUp == mib(1))
}

@Test func foldingKeepsTotalsExact() async throws {
    let root = try await build(projectTree(withNodeModules: true))
    #expect(root.totalTakesUp == ByteCount.gibibyte + ByteCount.gibibyte + mib(7))
}

// Final review, Critical 1: keeping is decided on a folder's TOTAL, so a big folder made only of small subfolders stays visible.
@Test func bigFolderMadeOfSmallSubfoldersIsKept() async throws {
    let reader = FakeVolumeReader()
    reader.directory(app, [Entry.dir("node_modules")])
    reader.directory("\(app)/node_modules", (0..<20).map { Entry.dir("pkg\($0)") })
    for i in 0..<20 { reader.directory("\(app)/node_modules/pkg\(i)", [Entry.file("index.js", allocated: mib(100), fileID: UInt64(100 + i))]) }
    let root = try await build(reader)
    let modules = root.child("node_modules")
    #expect(!modules.isAggregate)
    #expect(modules.totalTakesUp == mib(2_000))
    #expect(modules.child("20 smaller folders").aggregateKind == .buildOutput)
}
