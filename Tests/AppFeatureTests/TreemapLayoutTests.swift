import AppFeature
import CoreGraphics
import Testing
import TestSupport

@Test(arguments: 0..<200) func squarifyProperties(seed: Int) {
    var rng = SeededRandom(seed: UInt64(seed))
    let items = (0..<Int.random(in: 1...60, using: &rng)).map { TreemapItem(id: $0, weight: Double.random(in: 0.001...1000, using: &rng)) }
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 520)
    let cells = TreemapLayout.squarify(items, in: bounds)
    let total = items.reduce(0) { $0 + $1.weight }
    #expect(cells.count == items.count)
    for c in cells {
        #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(c.rect))
        let expected = items[c.id].weight / total * bounds.width * bounds.height
        #expect(abs(c.rect.width * c.rect.height - expected) <= max(0.5, expected * 0.001))
    }
    for i in cells.indices { for j in cells.indices where j > i {
        let overlap = cells[i].rect.intersection(cells[j].rect)
        #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
    } }
    #expect(TreemapLayout.squarify(items, in: bounds).map(\.rect) == cells.map(\.rect))   // deterministic
}

@Test func nonPositiveWeightsAreOmitted() {
    let cells = TreemapLayout.squarify([TreemapItem(id: "a", weight: 0), TreemapItem(id: "b", weight: -3), TreemapItem(id: "c", weight: 2)],
                                       in: CGRect(x: 0, y: 0, width: 10, height: 10))
    #expect(cells.map(\.id) == ["c"])
}

@Test func emptyInputGivesNoCells() {
    #expect(TreemapLayout.squarify([TreemapItem<Int>](), in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
}

@Test func singleItemFillsTheBounds() throws {
    let bounds = CGRect(x: 5, y: 7, width: 300, height: 200)
    let cell = try #require(TreemapLayout.squarify([TreemapItem(id: 1, weight: 42)], in: bounds).first)
    #expect(abs(cell.rect.minX - bounds.minX) < 0.001 && abs(cell.rect.minY - bounds.minY) < 0.001)
    #expect(abs(cell.rect.width - bounds.width) < 0.001 && abs(cell.rect.height - bounds.height) < 0.001)
}

@Test func zeroSizeRectGivesZeroSizeCells() {
    let cells = TreemapLayout.squarify([TreemapItem(id: 1, weight: 1), TreemapItem(id: 2, weight: 2)], in: CGRect(x: 3, y: 4, width: 0, height: 50))
    #expect(cells.count == 2)
    #expect(cells.allSatisfy { $0.rect.width == 0 || $0.rect.height == 0 })
}

@Test func ordersByWeightThenInputOrder() {
    let items = [TreemapItem(id: "small", weight: 1), TreemapItem(id: "tieA", weight: 5), TreemapItem(id: "tieB", weight: 5)]
    #expect(TreemapLayout.squarify(items, in: CGRect(x: 0, y: 0, width: 10, height: 10)).map(\.id) == ["tieA", "tieB", "small"])
}
