import AppFeature
import Foundation
import SharedKernel
import Testing

private func luminance(_ rgb: UInt32) -> Double {
    func channel(_ value: UInt32) -> Double {
        let c = Double(value) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb >> 16 & 0xFF) + 0.7152 * channel(rgb >> 8 & 0xFF) + 0.0722 * channel(rgb & 0xFF)
}

private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}

private let filledParts: [DiskBarSegment.Part] = Kind.allCases.map { .kind($0) } + [.swap, .otherVolumes]

@Test func labelsOnFillsMeetContrastInBothAppearances() {
    for part in filledParts {
        let fill = KindPalette.hex(for: part)
        #expect(contrast(KindPalette.labelHex.light, fill.light) >= 4.5, "light \(part)")
        #expect(contrast(KindPalette.labelHex.dark, fill.dark) >= 4.5, "dark \(part)")
    }
}

@Test func everyPartHasTitleAndDescription() {
    for part in filledParts + [.free] {
        #expect(!KindPalette.title(for: part).isEmpty)
        #expect(!KindPalette.description(for: part).isEmpty)
    }
    #expect(KindPalette.title(for: .otherVolumes) == "macOS itself")
}
