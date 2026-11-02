import Catalog
import SharedKernel

/// The rules a real run uses: the scan rules, plus the record-backed rules for tool caches, runtimes and agent sessions.
public enum LiveCatalog {
    public static func rules(home: CanonicalPath) -> [any Rule] {
        ScanRules.all + ToolCacheAssembly.rules(home: home) + RuntimeAssembly.rules(home: home) + AgentAssembly.rules(home: home)
    }
}
