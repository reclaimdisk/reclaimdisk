import SwiftUI

public struct RootView: View {
    let model: ScanModel

    public init(model: ScanModel) { self.model = model }

    public var body: some View {
        OverviewView(model: model)
            .frame(minWidth: 760, minHeight: 560)
    }
}
