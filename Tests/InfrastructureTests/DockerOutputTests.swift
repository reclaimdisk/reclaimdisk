import Catalog
import SharedKernel
import Testing
@testable import Infrastructure

// Recorded from Docker 28.5.1 on macOS (`docker system df --format json`, `docker image ls --format json`,
// `docker volume ls --format json`, `docker ps -a --no-trunc --format json`), trimmed to the fields that matter.
private let systemDF = """
{"Active":"4","Reclaimable":"1.476GB (53%)","Size":"2.76GB","TotalCount":"12","Type":"Images"}
{"Active":"3","Reclaimable":"0B (0%)","Size":"194B","TotalCount":"5","Type":"Containers"}
{"Active":"5","Reclaimable":"1.808GB (21%)","Size":"8.238GB","TotalCount":"14","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"5.983GB","Size":"5.983GB","TotalCount":"718","Type":"Build Cache"}
"""

private let images = """
{"Containers":"0","CreatedAt":"2026-11-02 00:31:30 +0100 CET","ID":"60a3fe7f2d65","Repository":"tryit/web","Size":"351MB","Tag":"c1f3820"}
{"Containers":"N/A","CreatedAt":"2026-10-12 10:00:00 +0200 CEST","ID":"aaaaaaaaaaaa","Repository":"postgres","Size":"480MB","Tag":"18"}
{"Containers":"N/A","CreatedAt":"2026-09-20 08:15:42 +0200 CEST","ID":"cccccccccccc","Repository":"\\u003cnone\\u003e","Size":"1.2GB","Tag":"\\u003cnone\\u003e"}
"""

private let volumes = """
{"Driver":"local","Labels":"com.docker.volume.anonymous=","Name":"1b9f3490b05066d5eebf46c4e01d274da81e71605f4efed3b6e7a7e93c02127b"}
{"Driver":"local","Labels":"com.docker.compose.project=app,com.docker.compose.volume=pgdata","Name":"app_pgdata"}
{"Driver":"local","Labels":"","Name":"app_redis"}
"""

private let containers = """
{"ID":"0f1e","Image":"postgres:18","Mounts":"app_redis","Names":"db","State":"running"}
{"ID":"9a8b","Image":"sha256:cccccccccccc0000000000000000000000000000000000000000000000000000","Mounts":"","Names":"old","State":"exited"}
"""

@Test func dockerSizesUseDecimalUnits() {
    #expect(DockerOutput.size("5.983GB") == ByteCount(5_983_000_000))
    #expect(DockerOutput.size("1.808GB (21%)") == ByteCount(1_808_000_000))
    #expect(DockerOutput.size("351MB") == ByteCount(351_000_000))
    #expect(DockerOutput.size("12.5kB") == ByteCount(12_500))
    #expect(DockerOutput.size("194B") == ByteCount(194))
    #expect(DockerOutput.size("0B (0%)") == .zero)
    #expect(DockerOutput.size("1.5TB") == ByteCount(1_500_000_000_000))
    #expect(DockerOutput.size("lots") == nil)
    #expect(DockerOutput.size("") == nil)
}

@Test func systemDFGivesReclaimableBuildCacheAndAnonymousVolumes() throws {
    let summary = try #require(DockerOutput.systemDF(systemDF))
    #expect(summary.buildCacheReclaimable == ByteCount(5_983_000_000))
    #expect(summary.volumesReclaimable == ByteCount(1_808_000_000))
    #expect(DockerOutput.systemDF("{\"Type\":\"Build Cache\"") == nil)     // a broken line is never a guess
    #expect(DockerOutput.systemDF("") == nil)
}

@Test func imagesKnowWhichContainersUseThem() throws {
    let parsed = try #require(DockerOutput.images(images, containers: containers))
    #expect(parsed.map(\.reference) == ["tryit/web:c1f3820", "postgres:18", "cccccccccccc"])
    #expect(parsed.map(\.usedByContainer) == [false, true, true])   // by reference, and by image id
    #expect(parsed[0].size == ByteCount(351_000_000))
    #expect(parsed[0].createdAt == Instant(nanosecondsSince1970: 1_793_575_890 * 1_000_000_000))   // 2026-11-01T23:31:30Z
    #expect(DockerOutput.images("not json", containers: containers) == nil)
}

@Test func volumesKnowAnonymityAndUse() throws {
    let parsed = try #require(DockerOutput.volumes(volumes, containers: containers))
    #expect(parsed.map(\.name) == ["1b9f3490b05066d5eebf46c4e01d274da81e71605f4efed3b6e7a7e93c02127b", "app_pgdata", "app_redis"])
    #expect(parsed.map(\.isAnonymous) == [true, false, false])
    #expect(parsed.map(\.usedByContainer) == [false, false, true])
    #expect(DockerOutput.volumes("{", containers: containers) == nil)
}
