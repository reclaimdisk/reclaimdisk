@testable import AppFeature
import AppKit
import Application
import Foundation
import SharedKernel
import SwiftUI
import Testing
import TestSupport

/// Renders the finished Overview off-screen in both appearances. Set RECLAIMDISK_SNAPSHOT_DIR to also write PNGs
/// for a visual check; without it the test still proves both appearances render.
@Test @MainActor func overviewRendersInBothAppearances() async throws {
    let reader = FakeVolumeReader()
    let data = "/System/Volumes/Data"
    let gib = ByteCount.gibibyte.bytes
    reader.capacity(data, CapacityReading(total: ByteCount(926 * gib), available: ByteCount(153 * gib), availableForImportantUsage: ByteCount(160 * gib), usedByVolume: ByteCount(731 * gib)))
    reader.capacity("/System/Volumes/VM", CapacityReading(total: ByteCount(926 * gib), available: ByteCount(153 * gib), availableForImportantUsage: ByteCount(153 * gib), usedByVolume: ByteCount(17 * gib)))
    reader.directory(data, [Entry.dir("Users"), Entry.dir("Applications")])
    reader.directory("\(data)/Users", [Entry.dir("u")])
    reader.directory("\(data)/Users/u", [Entry.dir("Projects"), Entry.dir("Library")])
    reader.directory("\(data)/Users/u/Projects", [Entry.file("src.bin", allocated: ByteCount(70 * gib), fileID: 1), Entry.dir("node_modules")])
    reader.directory("\(data)/Users/u/Projects/node_modules", [Entry.file("deps.bin", allocated: ByteCount(24 * gib), fileID: 2)])
    reader.directory("\(data)/Users/u/Library", [Entry.dir("Caches"), Entry.dir("Mail")])
    reader.directory("\(data)/Users/u/Library/Caches", [Entry.file("c.bin", allocated: ByteCount(84 * gib), fileID: 3)])
    reader.failing("\(data)/Users/u/Library/Mail", .notPermitted)
    reader.directory("\(data)/Applications", [Entry.file("apps.bin", allocated: ByteCount(129 * gib), fileID: 4)])
    let model = ScanModel(runScan: RunScan(reader: reader, clock: FakeClock(), home: CanonicalPath("/Users/u")!))
    model.start()
    for _ in 0..<300 where { if case .finished = model.state { false } else { true } }() { try await Task.sleep(for: .milliseconds(10)) }
    guard case .finished = model.state else { Issue.record("scan did not finish: \(model.state)"); return }

    for scheme in [ColorScheme.light, .dark] {
        let view = OverviewContent(model: model)
            .frame(width: 900, height: 640)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "no image for \(scheme)")
        #expect(image.width == 1800 && image.height == 1280)
        #expect(distinctColors(in: image) >= 20, "the \(scheme) rendering is blank or nearly blank")
        if let directory = ProcessInfo.processInfo.environment["RECLAIMDISK_SNAPSHOT_DIR"] {
            let rep = NSBitmapImageRep(cgImage: image)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("overview-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}

/// Samples a grid of pixels; a blank render has one or two colors.
private func distinctColors(in image: CGImage) -> Int {
    let rep = NSBitmapImageRep(cgImage: image)
    var seen = Set<String>()
    for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
            if let color = rep.colorAt(x: x, y: y) {
                seen.insert("\(Int(color.redComponent * 255))-\(Int(color.greenComponent * 255))-\(Int(color.blueComponent * 255))")
            }
        }
    }
    return seen.count
}
