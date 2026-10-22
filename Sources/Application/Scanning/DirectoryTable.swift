import Inventory
import SharedKernel

/// Everything the scan keeps per folder, as parallel arrays indexed by folder number.
/// Only folders and large files are stored, never every file, which keeps memory small (spec criterion 4).
/// A folder's index is always larger than its parent's, so a reverse pass is a valid post-order.
struct DirectoryTable {
    struct LargeFile {
        let name: String
        let takesUp: UInt64
        let freesAtLeast: UInt64
        let modified: Int64
    }

    private(set) var parent: [Int32] = [-1]
    private(set) var name: [String]
    var ownTakesUp: [UInt64] = [0]
    var ownFreesAtLeast: [UInt64] = [0]
    var newestOwn: [Int64] = [Int64.min]
    /// Folders that failed to read or vanished: they contribute nothing and get no node.
    var excluded: [Bool] = [false]
    var markers: [Int32: Set<String>] = [:]
    var largeFiles: [Int32: [LargeFile]] = [:]
    var unreadable: [(folder: Int32, reason: UnreadableReason)] = []

    init(rootName: String) { name = [rootName] }

    var count: Int { parent.count }

    mutating func addFolder(named folderName: String, parent parentIndex: Int32) -> Int32 {
        parent.append(parentIndex)
        name.append(folderName)
        ownTakesUp.append(0)
        ownFreesAtLeast.append(0)
        newestOwn.append(Int64.min)
        excluded.append(false)
        return Int32(parent.count - 1)
    }

    /// Names from the root down to `folder` (empty for the root).
    func relativeComponents(of folder: Int32) -> [String] {
        var components: [String] = []
        var current = folder
        while current > 0 {
            components.append(name[Int(current)])
            current = parent[Int(current)]
        }
        return components.reversed()
    }

    func readPath(of folder: Int32, root: CanonicalPath) -> CanonicalPath? {
        relativeComponents(of: folder).reduce(Optional(root)) { path, component in path?.appending(component) }
    }
}
