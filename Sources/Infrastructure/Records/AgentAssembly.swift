import Catalog
import SharedKernel

enum AgentAssembly {
    static func rules(home _: CanonicalPath) -> [any Rule] { [] }
}
