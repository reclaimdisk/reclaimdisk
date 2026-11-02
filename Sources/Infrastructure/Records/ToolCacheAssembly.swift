import Catalog
import SharedKernel

/// Docker and package-cache rules. The readers run query commands only.
enum ToolCacheAssembly {
    static func rules(home: CanonicalPath) -> [any Rule] {
        ToolCacheRules.docker(LiveDockerRecords(home: home)) + [ToolCacheRules.packageCaches(LivePackageCacheRecords(home: home))]
    }
}
