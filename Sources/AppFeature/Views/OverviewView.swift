import AppKit
import Application
import Infrastructure
import Inventory
import SharedKernel
import SwiftUI

enum ByteText {
    static func nearest(_ bytes: ByteCount) -> String { ByteFormatting.string(bytes, rounding: .nearest) }
    static func down(_ bytes: ByteCount) -> String { ByteFormatting.string(bytes, rounding: .down) }
}

public struct OverviewView: View {
    let model: ScanModel

    public init(model: ScanModel) { self.model = model }

    public var body: some View {
        ScrollView { OverviewContent(model: model) }
    }
}

/// The Overview without its scroll container (ImageRenderer can't draw ScrollView contents).
struct OverviewContent: View {
    @Bindable var model: ScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.state {
            case .idle(let warning):
                IdleView(warning: warning, scanVolume: { model.start() }, scanFolder: { chooseFolder(model) })
            case .scanning(let progress):
                ScanningView(progress: progress, cancel: model.cancel)
            case .failed(let message):
                FailedView(message: message, retry: { model.start(model.lastRequest) })
            case .finished(let scan):
                FinishedOverview(scan: scan, rescan: { model.start(model.lastRequest) }, scanFolder: { chooseFolder(model) })
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
func chooseFolder(_ model: ScanModel) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Scan"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let path = try? PathResolver.resolve(url.path, currentDirectory: .root) else { return }
    model.start(ScanRequest(path: path))
}

private struct IdleView: View {
    let warning: String?
    let scanVolume: () -> Void
    let scanFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ProductInfo.displayName).font(.largeTitle.weight(.semibold))
            Text("See where your disk space goes. Every size shows what it takes up and what deleting it would free at least.")
                .foregroundStyle(.secondary)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack {
                Button("Scan Data volume", action: scanVolume).keyboardShortcut(.defaultAction)
                Button("Scan a folder…", action: scanFolder)
            }
        }
    }
}

private struct ScanningView: View {
    let progress: ScanProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text("Read \(ByteFormatting.grouped(progress.directoriesRead)) folders, \(ByteText.nearest(progress.bytesSeen))…")
                .monospacedDigit()
            if let path = progress.currentPath {
                Text(path.raw).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
    }
}

private struct FailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "xmark.octagon").foregroundStyle(.red)
            Button("Try again", action: retry)
        }
    }
}

struct FinishedOverview: View {
    let scan: Scan
    let rescan: () -> Void
    let scanFolder: () -> Void
    @Environment(\.colorScheme) private var scheme

    private static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    var body: some View {
        let data = scan.disk.data
        let usedPercent = data.total.bytes == 0 ? 0 : Int((Double(data.containerUsed.bytes) / Double(data.total.bytes) * 100).rounded())
        let segments = DiskBarModel.segments(for: scan)
        VStack(alignment: .leading, spacing: 18) {
            if scan.isWholeVolume {
                Text("\(ByteText.nearest(data.available)) free of \(ByteText.nearest(data.total)) · \(usedPercent) % used")
                    .font(.title.weight(.semibold))
            } else {
                Text(scan.root.path.raw).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text("Takes up \(ByteText.nearest(scan.root.footprint.takesUp)) · frees at least \(ByteText.down(scan.root.footprint.freesAtLeast))")
                    .foregroundStyle(.secondary)
            }
            DiskBarView(segments: segments)
            if scan.needsFullDiskAccess { fullDiskAccessNotice }
            key(segments)
            HStack {
                Button("Scan again", action: rescan)
                Button("Scan a folder…", action: scanFolder)
            }
        }
    }

    private var fullDiskAccessNotice: some View {
        let locked = scan.unreadable.filter { $0.reason == .notPermitted }
        return VStack(alignment: .leading, spacing: 6) {
            Label("Some folders need Full Disk Access", systemImage: "lock").font(.headline)
            Text("macOS keeps these folders locked until you grant Full Disk Access, so they aren't counted yet:")
                .foregroundStyle(.secondary)
            ForEach(locked.prefix(5), id: \.path) { area in
                Text(area.path.raw).font(.caption.monospaced())
            }
            Button("Open Full Disk Access settings") { NSWorkspace.shared.open(Self.fullDiskAccessURL) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func key(_ segments: [DiskBarSegment]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
                        if segment.part == .free {
                            FreeStripes()
                        } else {
                            KindPalette.color(for: segment.part, scheme: scheme)
                        }
                    }
                    .frame(width: 12, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(KindPalette.title(for: segment.part)).fontWeight(.semibold)
                            Spacer()
                            Text(ByteText.nearest(segment.bytes)).monospacedDigit()
                        }
                        Text(KindPalette.description(for: segment.part)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
