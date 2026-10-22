import CoreGraphics

public struct TreemapItem<ID: Hashable & Sendable>: Sendable {
    public let id: ID
    public let weight: Double

    public init(id: ID, weight: Double) {
        self.id = id
        self.weight = weight
    }
}

public enum TreemapLayout {
    /// Squarified layout (Bruls, Huizing, van Wijk 2000). Items with weight <= 0 are omitted.
    /// Output order follows input order after sorting by weight descending, ties broken by input order.
    public static func squarify<ID>(_ items: [TreemapItem<ID>], in rect: CGRect) -> [(id: ID, rect: CGRect)] {
        let sorted = items.enumerated()
            .filter { $0.element.weight > 0 }
            .sorted { ($0.element.weight, -$0.offset) > ($1.element.weight, -$1.offset) }
            .map(\.element)
        guard !sorted.isEmpty else { return [] }
        guard rect.width > 0, rect.height > 0 else {
            return sorted.map { ($0.id, CGRect(origin: rect.origin, size: .zero)) }
        }
        let totalWeight = sorted.reduce(0) { $0 + $1.weight }
        let scale = Double(rect.width * rect.height) / totalWeight
        let areas = sorted.map { $0.weight * scale }

        var result: [(id: ID, rect: CGRect)] = []
        result.reserveCapacity(sorted.count)
        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            while end < areas.count,
                  worstAspect(areas[start...end], side: side) <= worstAspect(areas[start..<end], side: side) {
                end += 1
            }
            let row = areas[start..<end]
            let rowArea = row.reduce(0, +)
            if remaining.width >= remaining.height {
                // A column on the left, items stacked top to bottom.
                let columnWidth = CGFloat(rowArea) / remaining.height
                var y = remaining.minY
                for (offset, area) in row.enumerated() {
                    let isLast = offset == row.count - 1
                    let height = isLast ? remaining.maxY - y : CGFloat(area) / columnWidth
                    result.append((sorted[start + offset].id, CGRect(x: remaining.minX, y: y, width: columnWidth, height: height)))
                    y += height
                }
                remaining = CGRect(x: remaining.minX + columnWidth, y: remaining.minY,
                                   width: max(0, remaining.width - columnWidth), height: remaining.height)
            } else {
                // A row along the top, items left to right.
                let rowHeight = CGFloat(rowArea) / remaining.width
                var x = remaining.minX
                for (offset, area) in row.enumerated() {
                    let isLast = offset == row.count - 1
                    let width = isLast ? remaining.maxX - x : CGFloat(area) / rowHeight
                    result.append((sorted[start + offset].id, CGRect(x: x, y: remaining.minY, width: width, height: rowHeight)))
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + rowHeight,
                                   width: remaining.width, height: max(0, remaining.height - rowHeight))
            }
            start = end
        }
        return result
    }

    /// The worst (largest) aspect ratio in a row laid along a side of length `side`.
    private static func worstAspect(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let largest = row.max(), let smallest = row.min() else { return .infinity }
        let sideSquared = side * side, sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }
}
