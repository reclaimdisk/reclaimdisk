import Catalog
import Foundation
import SharedKernel

/// `WorkspacePath` in a DerivedData folder's `info.plist`. Nil when the file or the key is absent.
struct LiveXcodeRecords: XcodeRecords {
    func workspacePath(ofDerivedData folder: CanonicalPath) -> String? {
        guard let plist = folder.appending("info.plist"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: plist.raw)),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let path = object["WorkspacePath"] as? String else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
