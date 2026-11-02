import SwiftUI

public struct RootView: View {
    let model: ScanModel
    let candidates: CandidatesModel

    public init(model: ScanModel) {
        self.init(model: model, candidates: .live())
    }

    public init(model: ScanModel, candidates: CandidatesModel) {
        self.model = model
        self.candidates = candidates
    }

    public var body: some View {
        TabView {
            OverviewView(model: model)
                .tabItem { Label("Overview", systemImage: "internaldrive") }
            mapTab
                .tabItem { Label("Map", systemImage: "square.grid.3x3") }
            cleanupTab
                .tabItem { Label("Cleanup", systemImage: "checklist") }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder private var mapTab: some View {
        if case .finished(let scan) = model.state {
            MapView(scan: scan).id(scan.startedAt)
        } else {
            Text("Run a scan on the Overview tab to see the map.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var cleanupTab: some View {
        if case .finished(let scan) = model.state {
            CleanupView(scan: scan, model: candidates).id(scan.startedAt)
        } else {
            Text("Run a scan on the Overview tab to see candidates.").foregroundStyle(.secondary)
        }
    }
}
