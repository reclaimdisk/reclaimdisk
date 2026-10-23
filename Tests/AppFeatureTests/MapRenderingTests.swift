import AppKit
import Foundation
import Inventory
import SharedKernel
import SwiftUI
import Testing
@testable import AppFeature

/// Renders the map pane and side list off-screen; RECLAIMDISK_SNAPSHOT_DIR also writes PNGs for a visual check.
@Test @MainActor func mapRendersInBothAppearances() throws {
    let navigator = MapNavigator(root: try mapTestTree())
    for scheme in [ColorScheme.light, .dark] {
        let view = HStack(spacing: 0) {
            TreemapPane(navigator: navigator).padding(16)
            SideListRows(navigator: navigator).padding(12).frame(width: 320, alignment: .top)
        }
        .frame(width: 1100, height: 620)
        .background(scheme == .dark ? Color.black : Color.white)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        var colors = Set<String>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
                if let c = rep.colorAt(x: x, y: y) { colors.insert("\(Int(c.redComponent * 255))-\(Int(c.greenComponent * 255))-\(Int(c.blueComponent * 255))") }
            }
        }
        #expect(colors.count >= 20, "the \(scheme) map rendering is blank or nearly blank")
        if let directory = ProcessInfo.processInfo.environment["RECLAIMDISK_SNAPSHOT_DIR"] {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("map-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}
