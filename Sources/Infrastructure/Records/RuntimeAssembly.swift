import Catalog
import SharedKernel

/// Xcode, simulator and Android rules. The readers run query commands only.
enum RuntimeAssembly {
    static func rules(home: CanonicalPath) -> [any Rule] {
        RuntimeRules.all(
            simulators: LiveSimulatorRecords(home: home), android: LiveAndroidRecords(home: home), xcode: LiveXcodeRecords()
        )
    }
}
