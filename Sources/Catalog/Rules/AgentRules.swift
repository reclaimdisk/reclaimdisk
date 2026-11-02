import SharedKernel

/// The record-backed rules for agent temp folders, agent worktrees, Gradle output and stale Rust objects.
public enum AgentRules {
    public static func all(
        sessions: any SessionRecords, git: any GitRecords, processes: any ProcessRecords, stale: any StaleBuildRecords
    ) -> [any Rule] {
        [
            AgentTempBuildOutputRule(sessions: sessions),
            AgentTempFoldersRule(sessions: sessions),
            AgentWorktreesRule(sessions: sessions, git: git, processes: processes),
            GradleBuildOutputRule(git: git),
            RustStaleObjectsRule(processes: processes, stale: stale),
        ]
    }
}

/// A session is live while its last activity is strictly inside the recent-activity window.
enum AgentSessionLiveness {
    static func isLive(_ lastActivity: Instant, now: Instant) -> Bool {
        let (window, overflowed) = RecentActivity.windowSeconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflowed else { return false }
        let (age, ageOverflowed) = now.nanosecondsSince1970.subtractingReportingOverflow(lastActivity.nanosecondsSince1970)
        if ageOverflowed { return lastActivity > now }
        return age < window
    }
}

private enum SessionClaim {
    case unknown
    case live
    case ended
}

/// Build output copied into an agent's temp folder. The copy needs no lockfile: rerunning the session rebuilds it.
private struct AgentTempBuildOutputRule: Rule {
    let id = RuleID("agent-temp-build-output")!
    let title = "Build output in an agent's temp folder"
    let sessions: any SessionRecords

    func evaluate(_ context: RuleContext) -> RuleResult {
        let selected = Self.selections(in: context.scan.folders(), home: context.home)
        guard !selected.isEmpty else { return RuleResult(candidates: [], notes: []) }
        let claim = Self.claims(sessions.sessions(), now: context.now)
        let candidates = selected.compactMap { folder -> Candidate? in
            let blocked = Self.blockedReason(for: folder.path, claim: claim)
            let sessionFact = blocked ?? "Its agent session has ended."
            let facts = Self.scanFacts(folder).compactMap { Evidence(fact: $0, source: .scan, observedAt: context.now) }
            let session = Evidence(fact: sessionFact, source: .sessionRecords, observedAt: context.now)
            return AgentCandidate.make(
                rule: id, title: title, kind: .buildOutput, folder: folder, context: context, reclaimClass: .rebuildable,
                estimate: AgentCandidate.measured(folder), evidence: facts + [session].compactMap { $0 },
                recovery: "Rebuilt if the session runs again", action: .deletePath(folder.path), blockedReason: blocked,
                explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }

    /// Rust build folders, `node_modules` beside package.json, and virtualenvs. One nested inside another is dropped.
    private static func selections(in folders: [ScannedFolder], home: CanonicalPath) -> [ScannedFolder] {
        let agent = folders.filter { AgentLocations.isAgentTemp($0.path) && !PersonalLocations.contains($0.path, home: home) }
        let rust = RustBuildFolders.outermost(in: agent)
        let rest = agent.filter { isNodeModules($0) || isVirtualenv($0) }
        var byPath: [CanonicalPath: ScannedFolder] = [:]
        for folder in rust + rest { byPath[folder.path] = folder }
        let matches = Array(byPath.values)
        return matches
            .filter { folder in !matches.contains { $0.path != folder.path && folder.path.isSameOrDescendant(of: $0.path) } }
            .sorted { $0.path < $1.path }
    }

    private static func isNodeModules(_ folder: ScannedFolder) -> Bool {
        folder.name == "node_modules" && folder.parentMarkers.contains("package.json")
    }

    private static func isVirtualenv(_ folder: ScannedFolder) -> Bool {
        (folder.name == ".venv" || folder.name == "venv") && folder.markers.contains("pyvenv.cfg")
    }

    private static func scanFacts(_ folder: ScannedFolder) -> [String] {
        if folder.markers.contains(".rustc_info.json") { return RustBuildFolders.facts(for: folder) }
        if folder.name == "node_modules" { return ["node_modules beside package.json."] }
        return ["\(folder.name) holds pyvenv.cfg."]
    }

    private static func claims(_ reading: SessionReading, now: Instant) -> (CanonicalPath) -> SessionClaim {
        switch reading {
        case .unreadable:
            return { _ in .unknown }
        case .read(let sessions):
            return { path in
                let owners = sessions.filter { session in
                    guard let temp = session.tempFolder else { return false }
                    return path.isSameOrDescendant(of: temp)
                }
                if owners.isEmpty { return .unknown }
                if owners.contains(where: { AgentSessionLiveness.isLive($0.lastActivity, now: now) }) { return .live }
                return .ended
            }
        }
    }

    private static func blockedReason(for path: CanonicalPath, claim: (CanonicalPath) -> SessionClaim) -> String? {
        switch claim(path) {
        case .live: "Its agent session was active in the last 24 hours"
        case .unknown: "Can't tell whether its agent session has ended"
        case .ended: nil
        }
    }
}

/// The session folder itself, once the session has ended. Reported so a person can look through it; nothing is deleted.
private struct AgentTempFoldersRule: Rule {
    let id = RuleID("agent-temp-folders")!
    let title = "Agent temp folder"
    let sessions: any SessionRecords

    func evaluate(_ context: RuleContext) -> RuleResult {
        let folders = context.scan.folders().filter {
            AgentLocations.isAgentTemp($0.path) && !PersonalLocations.contains($0.path, home: context.home)
        }
        guard !folders.isEmpty else { return RuleResult(candidates: [], notes: []) }
        guard case .read(let sessions) = sessions.sessions() else { return RuleResult(candidates: [], notes: []) }
        let candidates = folders.compactMap { folder -> Candidate? in
            let owners = sessions.filter { $0.tempFolder == folder.path }
            guard let session = owners.first,
                  owners.allSatisfy({ !AgentSessionLiveness.isLive($0.lastActivity, now: context.now) }) else { return nil }
            let evidence = [
                Evidence(fact: "Agent temp folder for a finished session.", source: .scan, observedAt: context.now),
                Evidence(
                    fact: "Session \(session.tool) \(session.id) has ended.", source: .sessionRecords, observedAt: context.now
                ),
            ].compactMap { $0 }
            return AgentCandidate.make(
                rule: id, title: title, kind: .agentSessions, folder: folder, context: context, reclaimClass: .reportOnly,
                estimate: AgentCandidate.measured(folder), evidence: evidence, recovery: nil, action: nil, blockedReason: nil,
                explanation: "It may hold notes or results from the session. Look through it, then delete it yourself if you don't need it."
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}

/// A linked Git worktree an agent tool created. Removal is `git worktree remove`, never forced.
private struct AgentWorktreesRule: Rule {
    let id = RuleID("agent-worktrees")!
    let title = "Agent worktree"
    let sessions: any SessionRecords
    let git: any GitRecords
    let processes: any ProcessRecords

    func evaluate(_ context: RuleContext) -> RuleResult {
        let folders = context.scan.folders().filter {
            AgentLocations.isAgentWorktree($0.path, home: context.home)
                && !PersonalLocations.contains($0.path, home: context.home)
        }
        guard !folders.isEmpty else { return RuleResult(candidates: [], notes: []) }
        let sessionReading = sessions.sessions()
        let processReading = processes.processes()
        let candidates = folders.compactMap { folder -> Candidate? in
            let reading = git.worktree(at: folder.path)
            if case .notAWorktree = reading { return nil }
            return candidate(folder, reading: reading, sessions: sessionReading, processes: processReading, context: context)
        }
        return RuleResult(candidates: candidates, notes: [])
    }

    private func candidate(
        _ folder: ScannedFolder, reading: WorktreeReading, sessions: SessionReading, processes: ProcessReading,
        context: RuleContext
    ) -> Candidate? {
        let state: WorktreeState?
        switch reading {
        case .notAWorktree: return nil
        case .unreadable: state = nil
        case .worktree(let value): state = value
        }
        let blocked = blockedReason(folder.path, state: state, reading: reading, sessions: sessions, processes: processes, now: context.now)
        let branch = state?.branch
        let recovery = recoveryText(path: folder.path, branch: branch)
        let action: CandidateAction?
        if let main = state?.mainRepository, let command = ToolCommand(executable: "git", arguments: [
            "-C", main.raw, "worktree", "remove", folder.path.raw,
        ]) {
            action = .toolCommand(command)
        } else if blocked != nil, let command = ToolCommand(executable: "git", arguments: ["worktree", "remove", folder.path.raw]) {
            // Git could not name the main repository, so the command stays incomplete and the candidate stays blocked.
            action = .toolCommand(command)
        } else {
            return nil
        }
        let gitFact: String
        if let state, let branch = state.branch {
            gitFact = "Linked Git worktree of \(state.mainRepository.raw) on \(branch)."
        } else if let state {
            gitFact = "Linked Git worktree of \(state.mainRepository.raw)."
        } else {
            gitFact = "Git could not read this worktree."
        }
        let sessionFact = sessionsFact(sessions)
        let evidence = [
            Evidence(fact: gitFact, source: .git, observedAt: context.now),
            Evidence(fact: sessionFact, source: .sessionRecords, observedAt: context.now),
        ].compactMap { $0 }
        return AgentCandidate.make(
            rule: id, title: title, kind: .agentSessions, folder: folder, context: context, reclaimClass: .toolManaged,
            estimate: AgentCandidate.measured(folder), evidence: evidence, recovery: recovery, action: action,
            blockedReason: blocked, explanation: nil
        )
    }

    /// With no branch there is nothing to add the worktree back from, so the recovery says to make one first.
    private func recoveryText(path: CanonicalPath, branch: String?) -> String {
        if let branch, !branch.isEmpty {
            return "git worktree add \(path.raw) \(branch): the branch and its commits stay"
        }
        return "Give its commits a branch first: git -C \(path.raw) switch -c <name>"
    }

    private func sessionsFact(_ sessions: SessionReading) -> String {
        switch sessions {
        case .unreadable: "Agent session records could not be read."
        case .read: "Checked against recorded agent sessions."
        }
    }

    /// The first reason that applies. A worktree Git does not recognize is not a candidate at all.
    private func blockedReason(
        _ path: CanonicalPath, state: WorktreeState?, reading: WorktreeReading, sessions: SessionReading,
        processes: ProcessReading, now: Instant
    ) -> String? {
        if case .read(let recorded) = sessions,
           recorded.contains(where: { session in
               AgentSessionLiveness.isLive(session.lastActivity, now: now)
                   && session.workingDirectories.contains { $0.isSameOrDescendant(of: path) }
           }) {
            return "An agent session was using it in the last 24 hours."
        }
        if case .read(let running) = processes,
           running.contains(where: { $0.workingDirectory?.isSameOrDescendant(of: path) == true }) {
            return "A process is working inside it."
        }
        if let state {
            if state.hasChanges { return "It has uncommitted changes" }
            if !state.ignoredNonBuildPaths.isEmpty {
                let shown = state.ignoredNonBuildPaths.prefix(2).joined(separator: ", ")
                return "It holds ignored files that aren't build output: \(shown)"
            }
            if state.hasSubmodules { return "It has submodules." }
            if state.isLocked { return "It is locked." }
            if state.branch == nil { return "It has no branch, so removing it would leave its commits on no branch." }
        }
        if case .unreadable = reading { return "Can't read this worktree from Git." }
        if case .unreadable = sessions { return "Can't tell whether an agent session is using it." }
        return nil
    }
}

/// A Gradle `build` directory that Git already ignores.
private struct GradleBuildOutputRule: Rule {
    let id = RuleID("gradle-build-output")!
    let title = "Gradle build output"
    let git: any GitRecords

    func evaluate(_ context: RuleContext) -> RuleResult {
        let folders = context.scan.folders().filter(Self.qualifies)
        guard !folders.isEmpty else { return RuleResult(candidates: [], notes: []) }
        let candidates = folders.compactMap { folder -> Candidate? in
            guard !PersonalLocations.contains(folder.path, home: context.home) else { return nil }
            guard git.isIgnored(folder.path) == true else { return nil }
            let marker = folder.parentMarkers.contains("build.gradle.kts") ? "build.gradle.kts" : "build.gradle"
            let evidence = [
                Evidence(fact: "build beside \(marker).", source: .scan, observedAt: context.now),
                Evidence(fact: "Git ignores this folder.", source: .git, observedAt: context.now),
            ].compactMap { $0 }
            return AgentCandidate.make(
                rule: id, title: title, kind: .buildOutput, folder: folder, context: context, reclaimClass: .rebuildable,
                estimate: AgentCandidate.measured(folder), evidence: evidence, recovery: "gradle build",
                action: .deletePath(folder.path),
                blockedReason: RecentActivity.reason(newestChange: folder.newestChange, now: context.now), explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }

    private static func qualifies(_ folder: ScannedFolder) -> Bool {
        folder.name == "build"
            && (folder.parentMarkers.contains("build.gradle") || folder.parentMarkers.contains("build.gradle.kts"))
    }
}

/// Object files left inside a Rust build folder that was used within the last day. The folder itself stays.
private struct RustStaleObjectsRule: Rule {
    let id = RuleID("rust-stale-objects")!
    let title = "Stale objects in a busy Rust build folder"
    let processes: any ProcessRecords
    let stale: any StaleBuildRecords
    private static let untouchedSeconds: Int64 = 3_600
    private static let patterns = ["debug/deps/*.rcgu.o", "debug/incremental/*"]
    private static let minimumTakesUp = ByteCount(UInt64(256) * 1_048_576)
    private static let compilerNames: Set<String> = ["rustc", "cargo", "clippy-driver"]

    func evaluate(_ context: RuleContext) -> RuleResult {
        let busy = RustBuildFolders.outermost(in: context.scan.folders()).filter { folder in
            !PersonalLocations.contains(folder.path, home: context.home) && !AgentLocations.isAgentTemp(folder.path)
                && RecentActivity.reason(newestChange: folder.newestChange, now: context.now) != nil
        }
        guard !busy.isEmpty else { return RuleResult(candidates: [], notes: []) }
        let processReading = processes.processes()
        let blocked = Self.blockedReason(processReading)
        var candidates: [Candidate] = []
        var notes: [RuleNote] = []
        for folder in busy {
            switch stale.stale(in: folder.path, untouchedForSeconds: Self.untouchedSeconds, now: context.now) {
            case .unreadable:
                notes.append(RuleNote(rule: id, status: .unknown, reason: "The stale objects in \(folder.path.raw) could not be measured."))
            case .read(_, let takesUp, let freesAtLeast):
                guard takesUp >= Self.minimumTakesUp,
                      let estimate = try? Estimate.measured(freesAtLeast: freesAtLeast, takesUp: takesUp) else { continue }
                let evidence = (
                    RustBuildFolders.facts(for: folder).map { Evidence(fact: $0, source: .scan, observedAt: context.now) }
                        + [Evidence(
                            fact: "On macOS, Cargo keeps every object file for debug info.", source: .fileSystem,
                            observedAt: context.now
                        )]
                ).compactMap { $0 }
                if let candidate = AgentCandidate.make(
                    rule: id, title: title, kind: .buildOutput, folder: folder, context: context, reclaimClass: .rebuildable,
                    estimate: estimate, evidence: evidence, recovery: "cargo rebuilds them when needed",
                    action: .deleteStale(in: folder.path, patterns: Self.patterns, untouchedForSeconds: Self.untouchedSeconds),
                    blockedReason: blocked, explanation: nil
                ) {
                    candidates.append(candidate)
                }
            }
        }
        return RuleResult(candidates: candidates, notes: notes)
    }

    private static func blockedReason(_ reading: ProcessReading) -> String? {
        switch reading {
        case .unreadable: "Can't read the running processes"
        case .read(let running):
            running.contains { compilerNames.contains($0.name) } ? "A Rust build is running. Wait until it finishes." : nil
        }
    }
}

private enum AgentCandidate {
    static func measured(_ folder: ScannedFolder) -> Estimate? {
        try? Estimate.measured(freesAtLeast: folder.freesAtLeast, takesUp: folder.takesUp)
    }

    static func make(
        rule: RuleID, title: String, kind: Kind, folder: ScannedFolder, context: RuleContext, reclaimClass: ReclaimClass,
        estimate: Estimate?, evidence: [Evidence], recovery: String?, action: CandidateAction?, blockedReason: String?,
        explanation: String?
    ) -> Candidate? {
        guard let estimate else { return nil }
        return try? Candidate(
            rule: rule, title: title, kind: kind, target: .path(folder.path), reclaimClass: reclaimClass, estimate: estimate,
            evidence: evidence, recovery: recovery.flatMap(Recovery.init), action: action, newestChange: folder.newestChange,
            isInstalledRuntime: false, blockedReason: blockedReason, explanation: explanation
        )
    }
}
