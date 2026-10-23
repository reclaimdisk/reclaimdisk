import AppFeature
import Inventory
import SharedKernel
import Testing

@Test @MainActor func navigatorOpensGoesUpAndKeepsBreadcrumbs() throws {
    let tree = try mapTestTree()
    let navigator = MapNavigator(root: tree)
    navigator.up()
    #expect(navigator.current.path.raw == "/R")                                   // up from the root does nothing
    navigator.open(try #require(tree.find("/R/B")))
    #expect(navigator.current.path.raw == "/R")                                   // a leaf doesn't open
    navigator.open(path: CanonicalPath("/R/A/A1")!)
    #expect(navigator.current.path.raw == "/R/A/A1")
    #expect(navigator.breadcrumbs.map(\.path.raw) == ["/R", "/R/A", "/R/A/A1"])
    navigator.up()
    #expect(navigator.breadcrumbs.map(\.path.raw) == ["/R", "/R/A"])
    navigator.open(path: CanonicalPath("/R/missing")!)
    #expect(navigator.current.path.raw == "/R/A")                                 // unknown path: no change
    navigator.open(try #require(tree.find("/R/A/A1")))
    #expect(navigator.breadcrumbs.map(\.path.raw) == ["/R", "/R/A", "/R/A/A1"])
}
