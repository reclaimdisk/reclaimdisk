import Testing
@testable import SharedKernel

@Test(arguments: ["/", "/Users/a", "/private/tmp/x y", "/a/.hidden", "/a/b..c", "/a/🙂"])
func acceptsCanonical(_ raw: String) { #expect(CanonicalPath(raw)?.raw == raw) }

@Test(arguments: ["", "a/b", "//", "/a//b", "/a/", "/a/./b", "/a/../b", "/a/..", "/.", "/a\u{0}b"])
func rejectsNonCanonical(_ raw: String) { #expect(CanonicalPath(raw) == nil) }

@Test func descendantIsComponentWise() {
    let ab = CanonicalPath("/a/b")!
    #expect(CanonicalPath("/a/b/c")!.isSameOrDescendant(of: ab))
    #expect(ab.isSameOrDescendant(of: ab))
    #expect(!CanonicalPath("/a/bc")!.isSameOrDescendant(of: ab))
    #expect(CanonicalPath("/x")!.isSameOrDescendant(of: .root))
}

@Test func comparisonKeyIgnoresCaseAndNormalization() {
    #expect(CanonicalPath("/Users/A/Documents")!.comparisonKey == CanonicalPath("/users/a/documents")!.comparisonKey)
    #expect(CanonicalPath("/caf\u{e9}")!.comparisonKey == CanonicalPath("/cafe\u{301}")!.comparisonKey)   // Swift String equality is canonical
}

@Test func appendingRejectsSeparatorsAndDots() {
    let a = CanonicalPath("/a")!
    #expect(a.appending("b")?.raw == "/a/b")
    #expect(CanonicalPath.root.appending("b")?.raw == "/b")
    for bad in ["", ".", "..", "x/y", "x\u{0}"] { #expect(a.appending(bad) == nil) }
}

@Test func componentsParentAndLastComponent() {
    let p = CanonicalPath("/a/b/c")!
    #expect(p.components == ["a", "b", "c"])
    #expect(p.lastComponent == "c")
    #expect(p.parent?.raw == "/a/b")
    #expect(CanonicalPath("/a")!.parent == .root)
    #expect(CanonicalPath.root.parent == nil)
    #expect(CanonicalPath.root.components.isEmpty)
    #expect(CanonicalPath.root.lastComponent == "")
}

@Test func ordersByRawPath() {
    #expect(CanonicalPath("/D/A/x")! < CanonicalPath("/D/B/y")!)
}
