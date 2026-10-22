import SharedKernel

/// Spec 8.2 and 8.6: hard links and full clones, counted honestly.
/// - A hard-linked inode's allocated bytes go to the folder of its first path in canonical order; its private
///   bytes go to the lowest common ancestor of all its links, but only when every link was found.
/// - A full clone group (same clone id, refcount > 1) counts its blocks once in the scanned unique bytes.
struct LinkAndCloneAccounting {
    private struct LinkedInode {
        var linkCount: UInt32
        var allocated: UInt64
        var privateSize: UInt64
        var occurrences: [(folder: Int32, name: String)] = []
    }

    private struct CloneGroup {
        var smallestAllocated: UInt64
        var members: Set<UInt64> = []
    }

    private var linked: [UInt64: LinkedInode] = [:]
    private var clones: [UInt64: CloneGroup] = [:]

    mutating func recordLink(fileID: UInt64, linkCount: UInt32, allocated: UInt64, privateSize: UInt64, folder: Int32, name: String) {
        linked[fileID, default: LinkedInode(linkCount: linkCount, allocated: allocated, privateSize: privateSize)]
            .occurrences.append((folder, name))
    }

    mutating func recordClone(cloneID: UInt64, fileID: UInt64, allocated: UInt64) {
        var group = clones[cloneID] ?? CloneGroup(smallestAllocated: allocated)
        group.smallestAllocated = min(group.smallestAllocated, allocated)
        group.members.insert(fileID)
        clones[cloneID] = group
    }

    /// Adds every hard-linked inode's bytes to the table, before folding.
    func applyLinks(to table: inout DirectoryTable) {
        for inode in linked.values {
            let paths = inode.occurrences.map { (folder: $0.folder, path: (table.relativeComponents(of: $0.folder) + [$0.name]).joined(separator: "/")) }
            guard let first = paths.min(by: { $0.path < $1.path }) else { continue }
            table.ownTakesUp[Int(first.folder)] += inode.allocated
            guard inode.occurrences.count == Int(inode.linkCount) else { continue }
            let lca = lowestCommonAncestor(of: inode.occurrences.map(\.folder), in: table)
            table.ownFreesAtLeast[Int(lca)] += inode.privateSize
        }
    }

    /// Bytes counted more than once because full clones share their blocks.
    var cloneDuplicateBytes: UInt64 {
        clones.values.reduce(0) { $0 + $1.smallestAllocated * UInt64(max(0, $1.members.count - 1)) }
    }

    private func lowestCommonAncestor(of folders: [Int32], in table: DirectoryTable) -> Int32 {
        let chains = folders.map { folder -> [Int32] in
            var chain: [Int32] = []
            var current = folder
            while current >= 0 {
                chain.append(current)
                current = table.parent[Int(current)]
            }
            return chain.reversed()   // root first
        }
        guard var common = chains.first else { return 0 }
        for chain in chains.dropFirst() {
            common = Array(zip(common, chain).prefix { $0 == $1 }.map(\.0))
        }
        return common.last ?? 0
    }
}
