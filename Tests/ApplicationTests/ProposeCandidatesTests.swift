import Application
import Catalog
import Inventory
import SharedKernel
import Testing
import TestSupport

private let data = "/System/Volumes/Data"
private let home = CanonicalPath("/Users/u")!
private let later = Instant(nanosecondsSince1970: 1_800_000_000_000_000_000)

/// A Data volume with one project whose small node_modules holds ten packages, each with its own package.json and a
/// nested 2 MiB node_modules, plus a lockfile project under Documents.
private func volume() -> FakeVolumeReader {
    let reader = FakeVolumeReader(defaultDeviceID: 1)
    reader.capacity(data, CapacityReading(total: mib(10_000), available: mib(2_000), availableForImportantUsage: mib(2_500), usedByVolume: mib(7_000)))
    reader.directory(data, [Entry.dir("Users")])
    reader.directory("\(data)/Users", [Entry.dir("u")])
    reader.directory("\(data)/Users/u", [Entry.dir("Projects"), Entry.dir("Documents")])
    reader.directory("\(data)/Users/u/Projects", [Entry.dir("web")])
    reader.directory("\(data)/Users/u/Projects/web", [
        Entry.file("package.json", allocated: ByteCount(4_096), fileID: 10),
        Entry.file("pnpm-lock.yaml", allocated: ByteCount(4_096), fileID: 11),
        Entry.dir("node_modules"),
    ])
    reader.directory("\(data)/Users/u/Projects/web/node_modules", (0..<10).map { Entry.dir("pkg\($0)") })
    for index in 0..<10 {
        reader.directory("\(data)/Users/u/Projects/web/node_modules/pkg\(index)", [
            Entry.file("package.json", allocated: ByteCount(4_096), fileID: UInt64(1_000 + index)),
            Entry.file("index.js", allocated: ByteCount(65_536), fileID: UInt64(2_000 + index)),
            Entry.dir("node_modules"),
        ])
        reader.directory("\(data)/Users/u/Projects/web/node_modules/pkg\(index)/node_modules", [
            Entry.file("dep.js", allocated: mib(2), fileID: UInt64(3_000 + index)),
        ])
    }
    reader.directory("\(data)/Users/u/Documents", [Entry.dir("thesis")])
    reader.directory("\(data)/Users/u/Documents/thesis", [
        Entry.file("package.json", allocated: ByteCount(4_096), fileID: 20),
        Entry.file("package-lock.json", allocated: ByteCount(4_096), fileID: 21),
        Entry.dir("node_modules"),
    ])
    reader.directory("\(data)/Users/u/Documents/thesis/node_modules", [Entry.file("big.js", allocated: mib(50), fileID: 22)])
    return reader
}

private func scan() async throws -> Scan {
    try await RunScan(reader: volume(), clock: FakeClock(), home: home)(ScanRequest(), progress: { _ in })
}

private func folders(named name: String, in node: Node) -> [String] {
    (node.name == name && !node.isFile && !node.isAggregate ? [node.path.raw] : []) + node.children.flatMap { folders(named: name, in: $0) }
}

private struct FixedRule: Rule {
    let id = RuleID("fixed-rule")!
    let title = "Fixed rule"
    let paths: [String]
    func evaluate(_ context: RuleContext) -> RuleResult {
        let candidates = paths.map { raw -> Candidate in
            let path = CanonicalPath(raw)!
            return try! Candidate(
                rule: id, title: title, kind: .caches, target: .path(path), reclaimClass: .rebuildable,
                estimate: try! .measured(freesAtLeast: ByteCount(1), takesUp: ByteCount(1)),
                evidence: [Evidence(fact: "fixture", source: .scan, observedAt: context.now)!], recovery: Recovery("refills"),
                action: .deletePath(path), newestChange: nil, isInstalledRuntime: false, blockedReason: nil, explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [RuleNote(rule: id, status: .notApplicable, reason: "fixture note")])
    }
}

@Test func smallDependencyFoldersAreKeptButNestedOnesAndPackageFoldersAreNot() async throws {
    let root = try await scan().root
    #expect(folders(named: "node_modules", in: root).sorted() == [
        "/Users/u/Documents/thesis/node_modules", "/Users/u/Projects/web/node_modules",
    ])
    #expect(folders(named: "pkg0", in: root).isEmpty)   // a package.json alone does not keep a folder
}

@Test func candidatesComeFromTheScanAndNeverFromPersonalFolders() async throws {
    let list = await ProposeCandidates(rules: ScanRules.all, clock: FakeClock(start: later), home: home)(try await scan())
    #expect(list.candidates.map(\.id.rawValue) == ["node-dependencies:/Users/u/Projects/web/node_modules"])
    #expect(list.candidates.first?.estimate.takesUp == ByteCount(10 * (4_096 + 65_536 + 2_097_152)))
    #expect(list.candidates.first?.recovery?.text == "pnpm install")
    #expect(list.candidates.first?.isPreselected == true)
    #expect(list.generatedAt == later)
}

@Test func theUseCaseDropsPersonalFolderCandidatesWhateverTheRuleSays() async throws {
    let rule = FixedRule(paths: ["/Users/u/Documents/x/cache", "/Users/u/documents/y/cache", "/Users/u/Desktop/z", "/Users/u/Projects/w/cache"])
    let list = await ProposeCandidates(rules: [rule], clock: FakeClock(start: later), home: home)(try await scan())
    #expect(list.candidates.map(\.id.rawValue) == ["fixed-rule:/Users/u/Projects/w/cache"])
    #expect(list.notes == [RuleNote(rule: RuleID("fixed-rule")!, status: .notApplicable, reason: "fixture note")])
}

@Test func theKindFilterKeepsOnlyThatKind() async throws {
    let rules: [any Rule] = ScanRules.all + [FixedRule(paths: ["/Users/u/Projects/w/cache"])]
    let scanned = try await scan()
    let caches = await ProposeCandidates(rules: rules, clock: FakeClock(start: later), home: home)(scanned, kind: .caches)
    #expect(caches.candidates.map(\.id.rawValue) == ["fixed-rule:/Users/u/Projects/w/cache"])
    let build = await ProposeCandidates(rules: rules, clock: FakeClock(start: later), home: home)(scanned, kind: .buildOutput)
    #expect(build.candidates.map(\.id.rawValue) == ["node-dependencies:/Users/u/Projects/web/node_modules"])
}
