import Catalog
import Inventory
import SharedKernel

/// The kept folders of a scan, root included. Files and aggregates are not folders a rule can propose.
public struct ScanCatalogQuery: ScanQuery {
    private let scan: Scan

    public init(_ scan: Scan) { self.scan = scan }

    public func folders() -> [ScannedFolder] {
        var found: [ScannedFolder] = []
        walk(scan.root, parentMarkers: [], into: &found)
        return found
    }

    private func walk(_ node: Node, parentMarkers: Set<String>, into found: inout [ScannedFolder]) {
        let markersForChildren: Set<String>
        if node.isFile || node.isAggregate {
            markersForChildren = parentMarkers
        } else {
            if let folder = ScannedFolder(
                path: node.path, kind: node.kind, takesUp: node.footprint.takesUp, freesAtLeast: node.footprint.freesAtLeast,
                newestChange: node.newestChange, markers: node.markers, parentMarkers: parentMarkers
            ) {
                found.append(folder)
            }
            markersForChildren = node.markers
        }
        for child in node.children { walk(child, parentMarkers: markersForChildren, into: &found) }
    }
}
