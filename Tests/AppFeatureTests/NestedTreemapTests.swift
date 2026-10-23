import AppFeature
import CoreGraphics
import Inventory
import SharedKernel
import Testing

private let bounds = CGRect(x: 0, y: 0, width: 800, height: 520)

private func cell(_ cells: [TreemapCell], _ id: String) throws -> TreemapCell { try #require(cells.first { $0.id == id }, "no cell \(id)") }

@Test func cellsStayInsideAndNestBelowHeaders() throws {
    let cells = NestedTreemap.cells(for: try mapTestTree(), in: bounds)
    for c in cells { #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(c.rect), "\(c.id) escapes the bounds") }
    let a = try cell(cells, "/R/A"), a1 = try cell(cells, "/R/A/A1"), x = try cell(cells, "/R/A/A1/x")
    #expect(a.depth == 1 && a1.depth == 2 && x.depth == 3)
    #expect(a.rect.insetBy(dx: -0.01, dy: -0.01).contains(a1.rect))
    #expect(a1.rect.minY >= a.rect.minY + 20 - 0.01)                      // below the depth-1 header
    #expect(a1.rect.insetBy(dx: -0.01, dy: -0.01).contains(x.rect))
    #expect(x.rect.minY >= a1.rect.minY + 16 - 0.01)                      // below the depth-2 header
}

@Test func zeroSizeNodesGetNoCell() throws {
    #expect(!NestedTreemap.cells(for: try mapTestTree(), in: bounds).contains { $0.id == "/R/Z" })
}

@Test func ownFilesGetACellAndProportionsIncludeThem() throws {
    let cells = NestedTreemap.cells(for: try mapTestTree(), in: bounds)
    let own = try cell(cells, "/R#files")
    #expect(own.depth == 1)
    let total = 218.0, area = Double(bounds.width * bounds.height)
    for (id, bytes) in [("/R#files", 10.0), ("/R/A", 100.0), ("/R/B", 100.0)] {
        let c = try cell(cells, id)
        #expect(abs(Double(c.rect.width * c.rect.height) / area - bytes / total) < 0.001, "\(id) area not proportional")
    }
    #expect(cells.contains { $0.id == "/R/A/A1#files" && $0.depth == 3 })
    #expect(!cells.contains { $0.id == "/R/A#files" })                    // A has no own files
}

@Test func cellIDsAreUniqueEvenWhenAFolderLooksLikeAnAggregate() throws {
    let ids = NestedTreemap.cells(for: try mapTestTree(), in: bounds).map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ids.contains("/R/.smaller-other#aggregate") && ids.contains("/R/.smaller-other"))
}

@Test func labelsFollowTheSizeThresholds() throws {
    let cells = NestedTreemap.cells(for: try mapTestTree(), in: bounds)
    for c in cells {
        let isGroup = cells.contains { $0.depth == c.depth + 1 && $0.rect.minX >= c.rect.minX - 0.01 && $0.rect.maxX <= c.rect.maxX + 0.01
                                       && $0.rect.minY >= c.rect.minY - 0.01 && $0.rect.maxY <= c.rect.maxY + 0.01 }
        let (w, h) = (c.rect.width, c.rect.height)
        let expected = c.depth == 1 ? (w >= 46 && h >= 16) : (c.depth == 2 && isGroup ? (w >= 50 && h >= 14) : (w >= 58 && h >= 32))
        #expect(c.showsLabel == expected, "\(c.id) \(w)x\(h)")
    }
    #expect(try cell(cells, "/R/B").showsLabel)
    let tiny = NestedTreemap.cells(for: try mapTestTree(), in: CGRect(x: 0, y: 0, width: 60, height: 40))
    #expect(tiny.contains { !$0.showsLabel })
}

@Test func openTargetFollowsTheDepthRules() throws {
    let tree = try mapTestTree()
    let cells = NestedTreemap.cells(for: tree, in: bounds)
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R/A/A1/x"), in: cells)?.path.raw == "/R/A/A1")   // depth 3 -> its depth-2 parent
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R/A/A1"), in: cells)?.path.raw == "/R/A/A1")     // depth-2 group opens itself
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R/A/A2"), in: cells)?.path.raw == "/R/A")        // depth-2 leaf -> parent
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R/A"), in: cells)?.path.raw == "/R/A")           // depth-1 with children
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R/B"), in: cells) == nil)                        // depth-1 leaf
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R#files"), in: cells) == nil)
    #expect(NestedTreemap.openTarget(for: try cell(cells, "/R/.smaller-other#aggregate"), in: cells) == nil)
}
