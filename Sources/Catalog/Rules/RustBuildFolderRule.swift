import SharedKernel

/// Cargo's build directory, recognized by its marker files whatever the folder is called.
struct RustBuildFolderRule: Rule {
    let id = RuleID("rust-build-folder")!
    let title = "Rust build folder"
    private let markers: Set<String> = ["CACHEDIR.TAG", ".rustc_info.json"]

    func evaluate(_ context: RuleContext) -> RuleResult {
        let matches = context.scan.folders().filter { folder in
            folder.markers.isSuperset(of: markers) && !MeasuredPathCandidate.isProtected(folder, home: context.home)
        }
        let candidates = matches.compactMap { folder -> Candidate? in
            // A build folder nested inside another match is the same output, not a second candidate.
            let nested = matches.contains { other in other.path != folder.path && folder.path.isSameOrDescendant(of: other.path) }
            guard !nested else { return nil }
            var facts = ["Holds CACHEDIR.TAG and .rustc_info.json."]
            if folder.parentMarkers.contains("Cargo.toml") { facts.append("The parent folder holds Cargo.toml.") }
            return MeasuredPathCandidate.make(
                rule: id, title: title, folder: folder, context: context, reclaimClass: .rebuildable, facts: facts,
                recovery: "cargo build", explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}
