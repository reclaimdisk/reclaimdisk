import Catalog
import SharedKernel
import Testing

private struct NoFolders: ScanQuery {
    func folders() -> [ScannedFolder] { [] }
}

private struct FixedDocker: DockerRecords {
    let reading: DockerReading
    func read() -> DockerReading { reading }
}

/// Docker counts unused named volumes and unused anonymous volumes as one reclaimable total, while `volume prune` removes
/// only the anonymous ones. When Docker can't separate them, the candidate must not repeat Docker's total as its estimate.
@Test func anonymousVolumesWithoutTheirOwnTotalHaveAnUnknownEstimate() {
    let snapshot = DockerSnapshot(
        buildCacheReclaimable: .zero, images: [],
        volumes: [
            DockerVolume(name: "1b9f3490b05066d5", isAnonymous: true, usedByContainer: false),
            DockerVolume(name: "app_pgdata", isAnonymous: false, usedByContainer: false),
        ],
        anonymousVolumesReclaimable: nil, diskFile: nil
    )
    let context = RuleContext(scan: NoFolders(), home: CanonicalPath("/Users/u")!, now: Instant(nanosecondsSince1970: 1_800_000_000_000_000_000))
    let candidates = ToolCacheRules.docker(FixedDocker(reading: .read(snapshot))).flatMap { $0.evaluate(context).candidates }
    let anonymous = candidates.first { $0.rule.rawValue == "docker-anonymous-volumes" }
    #expect(anonymous?.estimate == .unknown)
    #expect(anonymous?.action == .toolCommand(ToolCommand(executable: "docker", arguments: ["volume", "prune", "-f"])!))
    #expect(anonymous?.evidence.contains { $0.fact.contains("1 anonymous volume") } == true)
}
