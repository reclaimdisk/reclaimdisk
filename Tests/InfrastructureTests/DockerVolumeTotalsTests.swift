import Catalog
@testable import Infrastructure
import SharedKernel
import Testing

/// `docker system df` adds every volume no container uses to "Local Volumes" reclaimable, named ones included.
@Test func dockersVolumeTotalIsTheAnonymousTotalOnlyWhenNoNamedVolumeIsUnused() {
    let total = ByteCount(1_808_000_000)
    let onlyAnonymousUnused = [
        DockerVolume(name: "1b9f3490b05066d5", isAnonymous: true, usedByContainer: false),
        DockerVolume(name: "app_redis", isAnonymous: false, usedByContainer: true),
    ]
    #expect(DockerOutput.anonymousVolumesReclaimable(total: total, volumes: onlyAnonymousUnused) == total)

    let namedUnused = onlyAnonymousUnused + [DockerVolume(name: "app_pgdata", isAnonymous: false, usedByContainer: false)]
    #expect(DockerOutput.anonymousVolumesReclaimable(total: total, volumes: namedUnused) == nil)
}
