import AppKit
import Application
import SharedKernel
import SwiftUI

/// Colors, titles and descriptions for the disk bar and the map. Every label color meets 4.5:1 on its fill
/// in both appearances (KindPaletteTests).
public enum KindPalette {
    public static let labelHex = (light: UInt32(0x121A22), dark: UInt32(0xF4F7FA))

    public static func hex(for part: DiskBarSegment.Part) -> (light: UInt32, dark: UInt32) {
        switch part {
        case .kind(.buildOutput): (0xF0A35B, 0xA95E28)
        case .kind(.agentSessions): (0xA98CE6, 0x6A4FB0)
        case .kind(.docker): (0x5E9BE3, 0x2E68AC)
        case .kind(.caches): (0xE3CB55, 0x80711A)
        case .kind(.apps): (0xE68DA9, 0x9C4665)
        case .kind(.developerTools): (0x93B56C, 0x52742F)
        case .kind(.projectSource): (0x4DBDAB, 0x20776A)
        case .kind(.personalFiles): (0xCDB898, 0x776549)
        case .kind(.macOSData): (0x9DB6C2, 0x3D5C6A)
        case .kind(.other): (0xB0B9C2, 0x4A5661)
        case .kind(.notReadable): (0xD9DFE5, 0x222B34)
        case .swap: (0x7D8C9B, 0x5D6B78)
        case .otherVolumes: (0x7B858E, 0x3A4651)
        case .free: (0xF1F4F6, 0x151D25)
        }
    }

    public static func color(for part: DiskBarSegment.Part) -> Color {
        let pair = hex(for: part)
        return dynamic(light: pair.light, dark: pair.dark)
    }

    public static var labelColor: Color { dynamic(light: labelHex.light, dark: labelHex.dark) }

    /// Scheme-aware variants for views (they also render correctly off-screen, where dynamic NSColors don't resolve).
    public static func color(for part: DiskBarSegment.Part, scheme: ColorScheme) -> Color {
        let pair = hex(for: part)
        return Color(nsColor: nsColor(scheme == .dark ? pair.dark : pair.light))
    }

    public static func labelColor(scheme: ColorScheme) -> Color {
        Color(nsColor: nsColor(scheme == .dark ? labelHex.dark : labelHex.light))
    }

    public static func title(for part: DiskBarSegment.Part) -> String {
        switch part {
        case .kind(let kind): KindTitles.title(for: kind)
        case .swap: "Swap"
        case .otherVolumes: "macOS itself"
        case .free: "Free"
        }
    }

    public static func description(for part: DiskBarSegment.Part) -> String {
        switch part {
        case .kind(.buildOutput): "target/, node_modules/, .next/, .venv/. Recreated by the next build."
        case .kind(.agentSessions): "Agent temp folders, .worktrees, agent transcripts."
        case .kind(.docker): "The Linux VM disk: images, build cache, containers, volumes."
        case .kind(.caches): "App and package caches. Refilled on demand."
        case .kind(.apps): "/Applications, Application Support, Containers."
        case .kind(.developerTools): "Xcode, simulators, Homebrew, toolchains."
        case .kind(.projectSource): "Repos in ~/Projects, minus their build output."
        case .kind(.personalFiles): "Documents, Desktop, Downloads, media, iCloud."
        case .kind(.macOSData): "Siri and language assets, system databases, sleep image."
        case .kind(.other): "Dotfiles, settings and folders that fit no group."
        case .kind(.notReadable): "System-only folders, file-system metadata and snapshots the scan can't attribute."
        case .swap: "Paged-out memory. Shrinks after memory pressure drops or a restart."
        case .otherVolumes: "System, Preboot and Recovery volumes. Not removable."
        case .free: "Unallocated space on the disk."
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
