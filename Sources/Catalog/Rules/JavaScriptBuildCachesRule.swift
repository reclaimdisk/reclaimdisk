import SharedKernel

/// Framework build caches that sit next to a package.json and come back on the next build.
struct JavaScriptBuildCachesRule: Rule {
    let id = RuleID("js-build-cache")!
    let title = "JavaScript build cache"
    private let names: Set<String> = [".next", ".turbo", ".parcel-cache", ".svelte-kit", ".nuxt"]

    func evaluate(_ context: RuleContext) -> RuleResult {
        let candidates = context.scan.folders().compactMap { folder -> Candidate? in
            guard names.contains(folder.name), folder.parentMarkers.contains("package.json") else { return nil }
            guard !MeasuredPathCandidate.isProtected(folder, home: context.home) else { return nil }
            return MeasuredPathCandidate.make(
                rule: id, title: title, folder: folder, context: context, reclaimClass: .rebuildable,
                facts: ["\(folder.name) beside package.json."], recovery: "The project's next build recreates it", explanation: nil
            )
        }
        return RuleResult(candidates: candidates, notes: [])
    }
}
