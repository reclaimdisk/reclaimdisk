import Catalog
import SharedKernel

enum AppAssembly {
    static func rules(home: CanonicalPath) -> [any Rule] {
        AppRules.all(
            playwright: LivePlaywrightRecords(cacheFolder: LivePlaywrightRecords.defaultCacheFolder(home: home)),
            apps: LiveAppRecords(home: home)
        )
    }
}
