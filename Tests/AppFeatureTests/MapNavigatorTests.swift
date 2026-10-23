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

/// The side list makes only these rows buttons, so VoiceOver never offers an action that does nothing.
@Test @MainActor func navigatorCanOpenOnlyFoldersWithChildren() throws {
    let tree = try mapTestTree()
    let navigator = MapNavigator(root: tree)
    #expect(navigator.canOpen(try #require(tree.find("/R/A"))))
    #expect(!navigator.canOpen(try #require(tree.find("/R/B"))))                       // a leaf
    #expect(!navigator.canOpen(try #require(tree.children.first { $0.isAggregate })))   // an aggregate
}
