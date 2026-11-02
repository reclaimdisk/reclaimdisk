import SharedKernel

/// A path candidate whose sizes come from the scanned folder. Scan rules share this so the class rules stay in one place.
enum MeasuredPathCandidate {
    static func isProtected(_ folder: ScannedFolder, home: CanonicalPath) -> Bool {
        PersonalLocations.contains(folder.path, home: home) || AgentLocations.isAgentTemp(folder.path)
            || InstalledSoftwareLocations.contains(folder.path, home: home)
    }

    static func make(
        rule: RuleID, title: String, folder: ScannedFolder, context: RuleContext, reclaimClass: ReclaimClass,
        facts: [String], recovery: String?, explanation: String?
    ) -> Candidate? {
        guard let estimate = try? Estimate.measured(freesAtLeast: folder.freesAtLeast, takesUp: folder.takesUp) else { return nil }
        let evidence = facts.compactMap { Evidence(fact: $0, source: .scan, observedAt: context.now) }
        let action: CandidateAction? = reclaimClass == .reportOnly ? nil : .deletePath(folder.path)
        return try? Candidate(
            rule: rule, title: title, kind: .buildOutput, target: .path(folder.path), reclaimClass: reclaimClass,
            estimate: estimate, evidence: evidence, recovery: recovery.flatMap(Recovery.init), action: action,
            newestChange: folder.newestChange, isInstalledRuntime: false,
            blockedReason: RecentActivity.reason(newestChange: folder.newestChange, now: context.now), explanation: explanation
        )
    }
}
