import Application
import Inventory

extension Node {
    /// The name as the app shows it: control characters escaped, the same way the CLI prints them.
    public var displayName: String { DisplayText.escaped(name) }
}
