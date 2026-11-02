import SharedKernel

/// Cargo's build directory, recognized by its marker files and layout whatever the folder is called.
struct RustBuildFolderRule: Rule {
    let id = RuleID("rust-build-folder")!
    let title = "Rust build folder"

    func evaluate(_ context: RuleContext) -> RuleResult {
        let candidates = RustBuildFolders.outermost(in: context.scan.folders()).compactMap { folder -> Candidate? in
            guard !MeasuredPathCandidate.isProtected(folder, home: context.home) else { return nil }
            var facts = RustBuildFolders.facts(for: folder)
            if folder.parentMarkers.contains("Cargo.toml") { facts.append("The parent folder holds Cargo.toml.") }
            return MeasuredPathCandidate.make(
                rule: id, title: title, folder: folder, context: context, reclaimClass: .rebuildable, facts: facts,
                recovery: "cargo build", explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}
