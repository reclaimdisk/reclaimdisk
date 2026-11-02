import SharedKernel

/// A virtualenv (`.venv` or `venv`) that holds `pyvenv.cfg`. A lock or requirements file makes it rebuildable.
struct PythonEnvironmentRule: Rule {
    let id = RuleID("python-environment")!
    let title = "Python environment"
    private let names: Set<String> = [".venv", "venv"]
    private let rebuilds: [(name: String, recovery: String)] = [
        ("uv.lock", "uv sync"),
        ("poetry.lock", "poetry install"),
        ("requirements.txt", "pip install -r requirements.txt"),
        ("requirements-dev.txt", "pip install -r requirements-dev.txt"),
    ]

    func evaluate(_ context: RuleContext) -> RuleResult {
        let candidates = context.scan.folders().compactMap { folder -> Candidate? in
            guard names.contains(folder.name), folder.markers.contains("pyvenv.cfg") else { return nil }
            guard !MeasuredPathCandidate.isProtected(folder, home: context.home) else { return nil }
            if let rebuild = rebuilds.first(where: { folder.parentMarkers.contains($0.name) }) {
                return MeasuredPathCandidate.make(
                    rule: id, title: title, folder: folder, context: context, reclaimClass: .rebuildable,
                    facts: ["\(folder.name) holds pyvenv.cfg, and the parent holds \(rebuild.name)."],
                    recovery: rebuild.recovery, explanation: nil
                )
            }
            return MeasuredPathCandidate.make(
                rule: id, title: title, folder: folder, context: context, reclaimClass: .reportOnly,
                facts: ["\(folder.name) holds pyvenv.cfg."], recovery: nil,
                explanation: "No lock or requirements file beside it, so it can't be rebuilt exactly."
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}
