import Catalog
import SharedKernel

enum RuntimeAssembly {
    static func rules(home _: CanonicalPath) -> [any Rule] { [] }
}
