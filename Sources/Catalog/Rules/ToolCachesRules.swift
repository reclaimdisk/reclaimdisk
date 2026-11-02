import SharedKernel

/// Rules for Docker's disk use and for package-manager caches. They only turn readings into candidates.
public enum ToolCacheRules {
    public static func docker(_ records: any DockerRecords) -> [any Rule] {
        DockerToolRule.Kind.all.map { DockerToolRule(kind: $0, records: records) }
    }

    public static func packageCaches(_ records: any PackageCacheRecords) -> any Rule {
        PackageCacheRule(records: records)
    }
}

private struct DockerToolRule: Rule {
    enum Kind: Sendable {
        case buildCache
        case unusedImages
        case anonymousVolumes
        case namedVolumes
        case diskFile

        static let all: [Kind] = [.buildCache, .unusedImages, .anonymousVolumes, .namedVolumes, .diskFile]

        var id: RuleID {
            switch self {
            case .buildCache: RuleID("docker-build-cache")!
            case .unusedImages: RuleID("docker-unused-images")!
            case .anonymousVolumes: RuleID("docker-anonymous-volumes")!
            case .namedVolumes: RuleID("docker-named-volumes")!
            case .diskFile: RuleID("docker-disk-file")!
            }
        }

        var title: String {
            switch self {
            case .buildCache: "Docker build cache"
            case .unusedImages: "Unused Docker images"
            case .anonymousVolumes: "Anonymous Docker volumes"
            case .namedVolumes: "Named Docker volume"
            case .diskFile: "Docker disk file"
            }
        }
    }

    let kind: Kind
    let records: any DockerRecords
    var id: RuleID { kind.id }
    var title: String { kind.title }

    func evaluate(_ context: RuleContext) -> RuleResult {
        switch records.read() {
        case .notInstalled:
            return noted(.notApplicable, "Docker isn't installed")
        case .notResponding(let reason):
            return noted(.unknown, "Docker isn't responding: \(reason)")
        case .unparseable(let reason):
            return noted(.unknown, "Docker's output couldn't be read: \(reason)")
        case .read(let snapshot):
            return RuleResult(candidates: candidates(from: snapshot, now: context.now), notes: [])
        }
    }

    private func noted(_ status: RuleNote.Status, _ reason: String) -> RuleResult {
        RuleResult(candidates: [], notes: [RuleNote(rule: id, status: status, reason: reason)])
    }

    private func candidates(from snapshot: DockerSnapshot, now: Instant) -> [Candidate] {
        switch kind {
        case .buildCache:
            return buildCache(snapshot, now: now)
        case .unusedImages:
            return unusedImages(snapshot, now: now)
        case .anonymousVolumes:
            return anonymousVolumes(snapshot, now: now)
        case .namedVolumes:
            return namedVolumes(snapshot, now: now)
        case .diskFile:
            return diskFile(snapshot, now: now)
        }
    }

    private func buildCache(_ snapshot: DockerSnapshot, now: Instant) -> [Candidate] {
        guard snapshot.buildCacheReclaimable > .zero,
              let estimate = try? Estimate.toolReported(tool: "docker", size: snapshot.buildCacheReclaimable),
              let command = ToolCommand(executable: "docker", arguments: ["builder", "prune", "-f"]) else { return [] }
        return one(
            estimate: estimate, fact: "Docker reports \(BinarySize.text(snapshot.buildCacheReclaimable)) of build cache.",
            source: .toolRecords("docker"), now: now, recovery: "Rebuilt on the next build", action: .toolCommand(command),
            target: .toolResource(tool: "docker", identifier: "build-cache"), reclaimClass: .toolManaged, explanation: nil
        )
    }

    /// `docker image prune --filter until=168h` drops images created at least 7 days ago.
    private func unusedImages(_ snapshot: DockerSnapshot, now: Instant) -> [Candidate] {
        let old = snapshot.images.filter { !$0.usedByContainer && isAtLeastSevenDaysOld($0.createdAt, now: now) }
        guard !old.isEmpty else { return [] }
        let reported = old.reduce(ByteCount.zero) { $0 + $1.size }
        guard let estimate = try? Estimate.toolReported(tool: "docker", size: reported),
              let command = ToolCommand(executable: "docker", arguments: ["image", "prune", "-a", "-f", "--filter", "until=168h"])
        else { return [] }
        let fact = "These images add up to \(BinarySize.text(reported)), but they share layers, so Docker may free less than their total."
        return one(
            estimate: estimate, fact: fact, source: .toolRecords("docker"), now: now, recovery: "Pull or build them again",
            action: .toolCommand(command), target: .toolResource(tool: "docker", identifier: "unused-images"),
            reclaimClass: .toolManaged, explanation: nil
        )
    }

    /// `volume prune` without `-a` removes only anonymous volumes, and their data is gone.
    private func anonymousVolumes(_ snapshot: DockerSnapshot, now: Instant) -> [Candidate] {
        let unused = snapshot.volumes.filter { $0.isAnonymous && !$0.usedByContainer }.count
        guard unused > 0, let command = ToolCommand(executable: "docker", arguments: ["volume", "prune", "-f"]) else { return [] }
        let estimate: Estimate
        let fact: String
        if let reported = snapshot.anonymousVolumesReclaimable {
            guard let toolReported = try? Estimate.toolReported(tool: "docker", size: reported) else { return [] }
            estimate = toolReported
            fact = "Docker reports \(BinarySize.text(reported)) in anonymous volumes no container uses."
        } else {
            estimate = .unknown
            let volumes = unused == 1 ? "1 anonymous volume is" : "\(unused) anonymous volumes are"
            fact = "\(volumes) not used by a container. Docker reports their size only together with unused named volumes."
        }
        return one(
            estimate: estimate, fact: fact, source: .toolRecords("docker"), now: now, recovery: "None: the data in them is lost",
            action: .toolCommand(command), target: .toolResource(tool: "docker", identifier: "anonymous-volumes"),
            reclaimClass: .toolManaged, explanation: nil
        )
    }

    private func namedVolumes(_ snapshot: DockerSnapshot, now: Instant) -> [Candidate] {
        snapshot.volumes.filter { !$0.isAnonymous && !$0.usedByContainer }.flatMap { volume in
            one(
                estimate: .unknown, fact: "Named volume \(volume.name) is not used by a container.", source: .toolRecords("docker"),
                now: now, recovery: nil, action: nil, target: .toolResource(tool: "docker", identifier: "volume/\(volume.name)"),
                reclaimClass: .reportOnly,
                explanation: "Named volumes can hold data you need, so ReclaimDisk never removes them."
            )
        }
    }

    private func diskFile(_ snapshot: DockerSnapshot, now: Instant) -> [Candidate] {
        guard let disk = snapshot.diskFile, let estimate = try? Estimate.measured(freesAtLeast: .zero, takesUp: disk.allocated) else {
            return []
        }
        let fact = "Docker's disk file takes up \(BinarySize.text(disk.allocated)) of its \(BinarySize.text(disk.maximum)) maximum."
        return one(
            estimate: estimate, fact: fact, source: .fileSystem, now: now, recovery: nil, action: nil, target: .path(disk.path),
            reclaimClass: .reportOnly,
            explanation: "Docker manages this file, and after a prune it shrinks only later, so free space can grow less than Docker reports at first."
        )
    }

    private func one(
        estimate: Estimate, fact: String, source: EvidenceSource, now: Instant, recovery: String?, action: CandidateAction?,
        target: Target, reclaimClass: ReclaimClass, explanation: String?
    ) -> [Candidate] {
        guard let evidence = Evidence(fact: fact, source: source, observedAt: now),
              let candidate = try? Candidate(
                  rule: id, title: title, kind: .docker, target: target, reclaimClass: reclaimClass, estimate: estimate,
                  evidence: [evidence], recovery: recovery.flatMap(Recovery.init), action: action, newestChange: nil,
                  isInstalledRuntime: false, blockedReason: nil, explanation: explanation
              ) else { return [] }
        return [candidate]
    }
}

/// Seven days, the same window as `docker image prune --filter until=168h`.
private func isAtLeastSevenDaysOld(_ created: Instant, now: Instant) -> Bool {
    let window = Int64(7) * 86_400 * 1_000_000_000
    let (age, ageOverflowed) = now.nanosecondsSince1970.subtractingReportingOverflow(created.nanosecondsSince1970)
    if ageOverflowed { return created < now }
    return age >= window
}

/// Binary size with one decimal, for a fact a person reads ("36.7 GiB").
private enum BinarySize {
    static func text(_ bytes: ByteCount) -> String {
        let unit: UInt64 = 1_073_741_824
        let half = unit / 2
        let (timesTen, timesOverflowed) = bytes.bytes.multipliedReportingOverflow(by: 10)
        let tenths: UInt64
        if timesOverflowed {
            tenths = bytes.bytes / (unit / 10)
        } else {
            let (sum, sumOverflowed) = timesTen.addingReportingOverflow(half)
            tenths = sumOverflowed ? timesTen / unit : sum / unit
        }
        return "\(tenths / 10).\(tenths % 10) GiB"
    }
}

private struct PackageCacheRule: Rule {
    let records: any PackageCacheRecords
    let id = RuleID("package-cache")!
    let title = "Package cache"

    func evaluate(_ context: RuleContext) -> RuleResult {
        var candidates: [Candidate] = []
        var notes: [RuleNote] = []
        for reading in records.read() {
            switch reading {
            case .notInstalled:
                continue
            case .unparseable(let tool, let reason):
                notes.append(RuleNote(rule: id, status: .unknown, reason: "\(tool): \(reason)"))
            case .found(let cache):
                if let candidate = candidate(for: cache, context: context) { candidates.append(candidate) }
            }
        }
        return RuleResult(candidates: candidates, notes: notes)
    }

    /// A folder the scan did not keep is below the listing threshold, so it is not a candidate.
    private func candidate(for cache: PackageCache, context: RuleContext) -> Candidate? {
        guard let folder = context.scan.folders().first(where: { sameFolder($0.path, cache.folder) }) else { return nil }
        // A partial cleaner does not empty the folder, so it cannot promise a minimum.
        let freesAtLeast = cache.clearsWholeFolder ? folder.freesAtLeast : .zero
        guard let estimate = try? Estimate.measured(freesAtLeast: freesAtLeast, takesUp: folder.takesUp),
              let evidence = Evidence(
                  fact: "\(cache.tool) keeps its cache in \(cache.folder.raw)", source: .toolRecords(cache.tool), observedAt: context.now
              ) else { return nil }
        return try? Candidate(
            rule: id, title: title, kind: .caches, target: .toolResource(tool: cache.tool, identifier: "cache"),
            reclaimClass: .toolManaged, estimate: estimate, evidence: [evidence], recovery: Recovery("Downloaded again when needed"),
            action: .toolCommand(cache.clean), newestChange: folder.newestChange, isInstalledRuntime: false,
            blockedReason: cache.busyReason, explanation: nil
        )
    }
}

/// `/System/Volumes/Data/Users` and `/Users` are the same folders. The scan of the Data volume records the first
/// form; a tool prints the second.
private func sameFolder(_ scanned: CanonicalPath, _ reported: CanonicalPath) -> Bool {
    folderKey(scanned) == folderKey(reported)
}

private func folderKey(_ path: CanonicalPath) -> String {
    let dataVolume = "/System/Volumes/Data"
    let stripped: String
    if path.raw == dataVolume {
        stripped = "/"
    } else if path.raw.hasPrefix(dataVolume + "/") {
        stripped = String(path.raw.dropFirst(dataVolume.count))
    } else {
        stripped = path.raw
    }
    return stripped.lowercased()
}
