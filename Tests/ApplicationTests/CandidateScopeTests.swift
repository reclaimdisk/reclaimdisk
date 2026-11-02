import Application
import Catalog
import Inventory
import SharedKernel
import Testing
import TestSupport

private let data = "/System/Volumes/Data"
private let home = CanonicalPath("/Users/u")!

/// One candidate inside the scanned folder, one path outside it, and one tool resource.
private struct EverywhereRule: Rule {
    let id = RuleID("everywhere")!
    let title = "Everywhere"

    func evaluate(_ context: RuleContext) -> RuleResult {
        let targets: [Target] = [
            .path(CanonicalPath("/Users/u/Projects/app/node_modules")!),
            .path(CanonicalPath("/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")!),
            .toolResource(tool: "docker", identifier: "build-cache"),
        ]
        let candidates = targets.compactMap { target in
            try? Candidate(
                rule: id, title: title, kind: .buildOutput, target: target, reclaimClass: .reportOnly, estimate: .unknown,
                evidence: [Evidence(fact: "seen", source: .scan, observedAt: context.now)!], recovery: nil, action: nil,
                newestChange: nil, isInstalledRuntime: false, blockedReason: nil, explanation: "Look at it."
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}

private func reader() -> FakeVolumeReader {
    let reader = FakeVolumeReader(defaultDeviceID: 1)
    reader.capacity(data, CapacityReading(total: mib(1000), available: mib(200), availableForImportantUsage: mib(250), usedByVolume: mib(700)))
    reader.directory(data, [Entry.dir("Users")])
    reader.directory("\(data)/Users", [Entry.file("f", allocated: mib(600), fileID: 1)])
    reader.directory("/Users/u/Projects", [Entry.file("a", allocated: mib(1), fileID: 2)])
    return reader
}

/// A folder run answers for that folder: candidates elsewhere on the disk, and tool resources, belong to a run over the
/// whole Data volume.
@Test func aFolderRunListsOnlyCandidatesInsideTheFolder() async throws {
    let scan = try await RunScan(reader: reader(), clock: FakeClock(), home: home)(
        ScanRequest(path: CanonicalPath("/Users/u/Projects")!), progress: { _ in }
    )
    let list = await ProposeCandidates(rules: [EverywhereRule()], clock: FakeClock(), home: home)(scan)
    #expect(list.candidates.map(\.id.rawValue) == ["everywhere:/Users/u/Projects/app/node_modules"])
}

@Test func aWholeVolumeRunListsCandidatesEverywhere() async throws {
    let scan = try await RunScan(reader: reader(), clock: FakeClock(), home: home)(ScanRequest(), progress: { _ in })
    let list = await ProposeCandidates(rules: [EverywhereRule()], clock: FakeClock(), home: home)(scan)
    #expect(list.candidates.count == 3)
}
