import SharedKernel

/// Decides a folder's Kind. Rules run in a fixed order and the first match wins:
/// specific rules, then the parent's kind, then location rules. Paths are user-facing.
public struct KindClassifier: Sendable {
    private let home: CanonicalPath

    public init(home: CanonicalPath) { self.home = home }

    public func kind(for path: CanonicalPath, name: String, markers: Set<String>, parentKind: Kind?) -> Kind {
        let subject = Subject(path: path, name: name, markers: markers, home: home)
        for rule in Self.specificRules {
            if let kind = rule(subject) { return kind }
        }
        if let parentKind, parentKind != .other { return parentKind }   // rule 7: inherit
        for rule in Self.locationRules {
            if let kind = rule(subject) { return kind }
        }
        return parentKind ?? .other                                      // rule 12
    }

    // MARK: rules, in order

    private typealias Rule = @Sendable (Subject) -> Kind?

    private static let specificRules: [Rule] = [
        { $0.components.contains("com.docker.docker") || $0.underHome([".docker"], ["Library", "Group Containers", "group.com.docker"]) ? .docker : nil },
        { $0.under(["System", "Library", "AssetsV2", "com_apple_MobileAsset_iOSSimulatorRuntime"]) || $0.isUnderXcodeApp ? .developerTools : nil },
        { $0.under(["System"]) || ($0.under(["private", "var"]) && !$0.under(["private", "var", "folders"])) ? .macOSData : nil },
        { buildOutputNames.contains($0.name) || $0.markers.isSuperset(of: cargoMarkers) ? .buildOutput : nil },
        { s in
            cacheNames.contains(s.name) || cacheNameSuffixes.contains { s.name.hasSuffix($0) }
                || s.under(["private", "var", "folders"]) || s.underHome(cacheHomePaths) ? .caches : nil
        },
        { s in
            s.isClaudeTemp || s.name == ".worktrees" || s.containsSequence([".claude", "worktrees"])
                || (s.homeRelative?.first.map { $0.hasPrefix(".claude") || $0.hasPrefix(".codex") } ?? false) ? .agentSessions : nil
        },
    ]

    private static let locationRules: [Rule] = [
        { s in
            s.underHome(developerHomePaths) || s.under(["opt"]) || s.under(["usr", "local"]) || s.under(["Library", "Developer"])
                ? .developerTools : nil
        },
        { $0.underHome(personalHomePaths) ? .personalFiles : nil },
        { $0.underHome(["Projects"]) ? .projectSource : nil },
        { s in
            s.under(["Applications"]) || s.underHome(["Library", "Application Support"], ["Library", "Containers"], ["Library", "Group Containers"])
                ? .apps : nil
        },
    ]

    // MARK: vocabulary

    private static let cargoMarkers: Set<String> = ["CACHEDIR.TAG", ".rustc_info.json"]
    private static let buildOutputNames: Set<String> = [
        "target", "node_modules", ".next", ".turbo", "dist", ".venv", "venv", "DerivedData", "__pycache__",
        ".parcel-cache", ".svelte-kit", ".nuxt", ".expo", "Pods",
    ]
    private static let cacheNames: Set<String> = [
        "Cache", "Caches", "CachedData", "Code Cache", "GPUCache", "Service Worker", "CacheStorage", "ShipIt", "cache", ".cache",
    ]
    private static let cacheNameSuffixes = ["Render Files", "Audio Previews", "Media Cache", "Media Cache Files"]
    private static let cacheHomePaths: [[String]] = [
        ["Library", "Caches"], [".cache"], [".npm"], [".bun", "install", "cache"], [".pnpm-store"], ["Library", "pnpm"],
        [".cargo", "registry"], [".cargo", "git"], [".gradle"], ["go", "pkg", "mod"], [".m2"],
    ]
    private static let developerHomePaths: [[String]] = [
        ["Library", "Developer"], ["Library", "Android"], [".rustup"], [".cargo"], [".nvm"], [".bun"], [".local"],
        [".pyenv"], [".vscode"], [".cursor"], ["go"], [".npm-global"], [".deno"],
    ]
    private static let personalHomePaths: [[String]] = [
        ["Documents"], ["Desktop"], ["Downloads"], ["Pictures"], ["Movies"], ["Music"],
        ["Library", "Mobile Documents"], ["Library", "CloudStorage"], ["Library", "Mail"], ["Library", "Messages"],
    ]
}

/// The facts one classification looks at, computed once per call.
private struct Subject {
    let name: String
    let markers: Set<String>
    let components: [String]
    /// Components below the home folder, or nil when the path isn't under it.
    let homeRelative: [String]?

    init(path: CanonicalPath, name: String, markers: Set<String>, home: CanonicalPath) {
        self.name = name
        self.markers = markers
        components = path.components
        homeRelative = path.isSameOrDescendant(of: home) ? Array(components.dropFirst(home.components.count)) : nil
    }

    func under(_ prefix: [String]) -> Bool {
        components.count >= prefix.count && Array(components.prefix(prefix.count)) == prefix
    }

    func underHome(_ prefixes: [String]...) -> Bool { underHome(prefixes) }

    func underHome(_ prefixes: [[String]]) -> Bool {
        guard let relative = homeRelative else { return false }
        return prefixes.contains { relative.count >= $0.count && Array(relative.prefix($0.count)) == $0 }
    }

    func containsSequence(_ sequence: [String]) -> Bool {
        guard components.count >= sequence.count else { return false }
        return (0...(components.count - sequence.count)).contains { Array(components[$0..<($0 + sequence.count)]) == sequence }
    }

    /// /private/tmp/claude-* and below.
    var isClaudeTemp: Bool {
        components.count >= 3 && components[0] == "private" && components[1] == "tmp" && components[2].hasPrefix("claude-")
    }

    /// /Applications/Xcode*.app and below.
    var isUnderXcodeApp: Bool {
        components.count >= 2 && components[0] == "Applications" && components[1].hasPrefix("Xcode") && components[1].hasSuffix(".app")
    }
}
