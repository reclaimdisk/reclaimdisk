import SharedKernel

/// A project's `node_modules`, not one nested inside another package.
struct NodeDependenciesRule: Rule {
    let id = RuleID("node-dependencies")!
    let title = "Node dependencies"

    /// First match wins, so a project with two lockfiles gets one recovery.
    private let lockfiles: [(name: String, recovery: String)] = [
        ("package-lock.json", "npm ci"),
        ("pnpm-lock.yaml", "pnpm install"),
        ("yarn.lock", "yarn install"),
        ("bun.lock", "bun install"),
        ("bun.lockb", "bun install"),
    ]

    func evaluate(_ context: RuleContext) -> RuleResult {
        let candidates = context.scan.folders().compactMap { folder -> Candidate? in
            guard folder.name == "node_modules", !MeasuredPathCandidate.isProtected(folder, home: context.home) else { return nil }
            guard folder.parentMarkers.contains("package.json") else { return nil }
            guard !folder.path.components.dropLast().contains("node_modules") else { return nil }
            if let lock = lockfiles.first(where: { folder.parentMarkers.contains($0.name) }) {
                return MeasuredPathCandidate.make(
                    rule: id, title: title, folder: folder, context: context, reclaimClass: .rebuildable,
                    facts: ["node_modules beside package.json and \(lock.name)."], recovery: lock.recovery, explanation: nil
                )
            }
            return MeasuredPathCandidate.make(
                rule: id, title: title, folder: folder, context: context, reclaimClass: .reportOnly,
                facts: ["node_modules beside package.json, with no lockfile."], recovery: nil,
                explanation: "No lockfile beside it, so reinstalling could pick different versions."
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}
