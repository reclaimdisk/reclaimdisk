import SwiftUI

public struct RootView: View {
    let model: ScanModel

    public init(model: ScanModel) { self.model = model }

    public var body: some View {
        TabView {
            OverviewView(model: model)
                .tabItem { Label("Overview", systemImage: "internaldrive") }
            mapTab
                .tabItem { Label("Map", systemImage: "square.grid.3x3") }
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
}
