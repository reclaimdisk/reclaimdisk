import SwiftUI

/// The whole disk as one bar; each segment's width is proportional to its bytes.
struct DiskBarView: View {
    let segments: [DiskBarSegment]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let total = max(1, segments.reduce(0) { $0 + Double($1.bytes.bytes) })
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = max(segment.bytes.bytes > 0 ? 1 : 0, geometry.size.width * Double(segment.bytes.bytes) / total)
                    if segment.part == .free {
                        FreeStripes().frame(width: width)
                    } else {
                        Rectangle().fill(KindPalette.color(for: segment.part, scheme: scheme)).frame(width: width)
                    }
                }
            }
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\(KindPalette.title(for: $0.part)) \(ByteText.nearest($0.bytes))" }.joined(separator: ", "))
    }
}

/// Free space: diagonal stripes, no fill.
struct FreeStripes: View {
    var body: some View {
        Canvas { context, size in
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                x += 7
            }
        }
    }
}
