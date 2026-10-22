import AppFeature
import AppKit
import SwiftUI

@main
struct ReclaimDiskApp: App {
    @State private var model = ScanModel.live()

    init() {
        // Launched with `swift run` there's no app bundle; this makes the window take focus.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("ReclaimDisk") { RootView(model: model) }
    }
}
