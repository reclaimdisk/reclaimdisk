import Catalog
import SharedKernel
import Testing

private let second: Int64 = 1_000_000_000
private let now = Instant(nanosecondsSince1970: 1_800_000_000 * second)
private let eightDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 8 * 86_400) * second)
private let twoDaysAgo = Instant(nanosecondsSince1970: (1_800_000_000 - 2 * 86_400) * second)
private let home = CanonicalPath("/Users/u")!
private let diskPath = CanonicalPath("/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")!

private struct Folders: ScanQuery {
    let list: [ScannedFolder]
    func folders() -> [ScannedFolder] { list }
}

private struct FixedDocker: DockerRecords {
    let reading: DockerReading
    func read() -> DockerReading { reading }
}

private struct FixedCaches: PackageCacheRecords {
    let readings: [PackageCacheReading]
    func read() -> [PackageCacheReading] { readings }
}

private func context(_ folders: [ScannedFolder] = []) -> RuleContext {
    RuleContext(scan: Folders(list: folders), home: home, now: now)
}

private func all(_ rules: [any Rule], _ ctx: RuleContext) -> RuleResult {
    rules.reduce(RuleResult(candidates: [], notes: [])) { sum, rule in
        let result = rule.evaluate(ctx)
        return RuleResult(candidates: sum.candidates + result.candidates, notes: sum.notes + result.notes)
    }
}

private let snapshot = DockerSnapshot(
    buildCacheReclaimable: ByteCount(5_983_000_000),
    images: [
        DockerImage(id: "60a3fe7f2d65", reference: "web:old", createdAt: eightDaysAgo, size: ByteCount(351_000_000), usedByContainer: false),
        DockerImage(id: "398a08e681fc", reference: "web:new", createdAt: twoDaysAgo, size: ByteCount(350_000_000), usedByContainer: false),
        DockerImage(id: "aaaaaaaaaaaa", reference: "postgres:18", createdAt: eightDaysAgo, size: ByteCount(480_000_000), usedByContainer: true),
        DockerImage(id: "bbbbbbbbbbbb", reference: "redis:7", createdAt: eightDaysAgo, size: ByteCount(40_000_000), usedByContainer: false),
    ],
    volumes: [
        DockerVolume(name: "1b9f3490b05066d5", isAnonymous: true, usedByContainer: false),
        DockerVolume(name: "4ddc9f6cfa90ac6b", isAnonymous: true, usedByContainer: true),
        DockerVolume(name: "app_pgdata", isAnonymous: false, usedByContainer: false),
        DockerVolume(name: "app_redis", isAnonymous: false, usedByContainer: true),
    ],
    anonymousVolumesReclaimable: ByteCount(1_808_000_000),
    diskFile: DockerDiskFile(path: diskPath, allocated: ByteCount(39_353_884_672), maximum: ByteCount(171_798_691_840))
)

@Test func dockerRulesListBuildCacheOldUnusedImagesVolumesAndTheDiskFile() {
    let result = all(ToolCacheRules.docker(FixedDocker(reading: .read(snapshot))), context())
    #expect(result.notes.isEmpty)
    #expect(result.candidates.map(\.id.rawValue).sorted() == [
        "docker-anonymous-volumes:docker/anonymous-volumes",
        "docker-build-cache:docker/build-cache",
        "docker-disk-file:\(diskPath.raw)",
        "docker-named-volumes:docker/volume/app_pgdata",
        "docker-unused-images:docker/unused-images",
    ])
    let byRule = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.rule.rawValue, $0) })

    let cache = byRule["docker-build-cache"]
    #expect(cache?.reclaimClass == .toolManaged)
    #expect(cache?.estimate.basis == .toolReported(tool: "docker"))
    #expect(cache?.estimate.reported == ByteCount(5_983_000_000))
    #expect(cache?.estimate.freesAtLeast == nil)
    #expect(cache?.action == .toolCommand(ToolCommand(executable: "docker", arguments: ["builder", "prune", "-f"])!))
    #expect(cache?.evidence.contains { $0.source == .toolRecords("docker") } == true)

    let images = byRule["docker-unused-images"]   // only web:old and redis:7: unused and older than 7 days
    #expect(images?.estimate.reported == ByteCount(391_000_000))
    #expect(images?.action == .toolCommand(ToolCommand(executable: "docker", arguments: ["image", "prune", "-a", "-f", "--filter", "until=168h"])!))

    let anonymous = byRule["docker-anonymous-volumes"]
    #expect(anonymous?.reclaimClass == .toolManaged)
    #expect(anonymous?.estimate.reported == ByteCount(1_808_000_000))
    #expect(anonymous?.action == .toolCommand(ToolCommand(executable: "docker", arguments: ["volume", "prune", "-f"])!))
    #expect(anonymous?.isPreselected == false)

    let named = byRule["docker-named-volumes"]
    #expect(named?.reclaimClass == .reportOnly)
    #expect(named?.action == nil)

    let disk = byRule["docker-disk-file"]
    #expect(disk?.reclaimClass == .reportOnly)
    #expect(disk?.estimate.takesUp == ByteCount(39_353_884_672))
    #expect(disk?.evidence.contains { $0.fact.contains("GiB") } == true)   // allocated against maximum, readable
    #expect(disk?.explanation?.lowercased().contains("later") == true)     // the file shrinks only after a while
}

@Test func dockerNotInstalledIsNotApplicableAndNotRespondingIsUnknown() {
    let missing = all(ToolCacheRules.docker(FixedDocker(reading: .notInstalled)), context())
    #expect(missing.candidates.isEmpty)
    #expect(!missing.notes.isEmpty && missing.notes.allSatisfy { $0.status == .notApplicable })

    let stuck = all(ToolCacheRules.docker(FixedDocker(reading: .notResponding("timed out after 10 s"))), context())
    #expect(stuck.candidates.isEmpty)
    #expect(!stuck.notes.isEmpty && stuck.notes.allSatisfy { $0.status == .unknown })

    let garbled = all(ToolCacheRules.docker(FixedDocker(reading: .unparseable("line 2 is not JSON"))), context())
    #expect(garbled.candidates.isEmpty)
    #expect(!garbled.notes.isEmpty && garbled.notes.allSatisfy { $0.status == .unknown })
}

@Test func emptyDockerResourcesProduceNoCandidates() {
    let empty = DockerSnapshot(buildCacheReclaimable: .zero, images: [], volumes: [], anonymousVolumesReclaimable: .zero, diskFile: nil)
    #expect(all(ToolCacheRules.docker(FixedDocker(reading: .read(empty))), context()).candidates.isEmpty)
}

@Test func packageCachesAreMeasuredFromTheScanAndUvWaitsForItsLock() {
    let folders = [
        ScannedFolder(path: CanonicalPath("/Users/u/.npm")!, kind: .caches, takesUp: ByteCount(2_000), freesAtLeast: ByteCount(1_800),
                      newestChange: twoDaysAgo, markers: [], parentMarkers: [])!,
        ScannedFolder(path: CanonicalPath("/Users/u/.cache/uv")!, kind: .caches, takesUp: ByteCount(9_000), freesAtLeast: ByteCount(8_000),
                      newestChange: twoDaysAgo, markers: [], parentMarkers: [])!,
    ]
    let readings: [PackageCacheReading] = [
        .found(PackageCache(tool: "npm", folder: CanonicalPath("/Users/u/.npm")!,
                            clean: ToolCommand(executable: "npm", arguments: ["cache", "clean", "--force"])!, clearsWholeFolder: true, busyReason: nil)),
        .found(PackageCache(tool: "uv", folder: CanonicalPath("/Users/u/.cache/uv")!,
                            clean: ToolCommand(executable: "uv", arguments: ["cache", "prune"])!, clearsWholeFolder: false,
                            busyReason: "uv is running (3 processes) and holds its cache lock")),
        .found(PackageCache(tool: "pip", folder: CanonicalPath("/Users/u/Library/Caches/pip")!,   // not in the scan: too small to list
                            clean: ToolCommand(executable: "pip", arguments: ["cache", "purge"])!, clearsWholeFolder: true, busyReason: nil)),
        .notInstalled(tool: "pnpm"),
        .unparseable(tool: "brew", reason: "brew --cache printed nothing"),
    ]
    let result = ToolCacheRules.packageCaches(FixedCaches(readings: readings)).evaluate(context(folders))
    #expect(result.candidates.map(\.id.rawValue).sorted() == ["package-cache:npm/cache", "package-cache:uv/cache"])
    let npm = result.candidates.first { $0.id.rawValue == "package-cache:npm/cache" }
    #expect(npm?.reclaimClass == .toolManaged)
    #expect(npm?.estimate.freesAtLeast == ByteCount(1_800))
    #expect(npm?.blockedReason == nil)
    let uv = result.candidates.first { $0.id.rawValue == "package-cache:uv/cache" }
    #expect(uv?.estimate.freesAtLeast == .zero)           // uv cache prune removes only unused entries
    #expect(uv?.estimate.takesUp == ByteCount(9_000))
    #expect(uv?.blockedReason == "uv is running (3 processes) and holds its cache lock")
    #expect(result.notes == [RuleNote(rule: RuleID("package-cache")!, status: .unknown, reason: "brew: brew --cache printed nothing")])
}
