import Inventory
import SharedKernel

/// Turns the finished table into the kept node tree: classify every folder,
/// keep the big or notable ones, and fold the rest into one aggregate per Kind under their kept parent.
enum Folding {
    static func rootDraft(table: DirectoryTable, options: ScanOptions, rootDisplayPath: CanonicalPath) -> NodeDraft {
        Builder(table: table, options: options).draft(folder: 0, path: rootDisplayPath, parentKind: nil)
    }

    private struct Builder {
        let table: DirectoryTable
        let options: ScanOptions
        let children: [[Int32]]
        let totalTakesUp: [UInt64]
        let newestTotal: [Int64]
        let keep: [Bool]
        /// Link credit that stays on its common ancestor, which is kept and holds a link outside its aggregates.
        let keptCredit: [Int32: UInt64]
        /// Link credit whose links all fold into one kept folder's aggregates, by that folder; placed once kinds are known.
        let foldedCredits: [Int32: [DirectoryTable.LinkCredit]]
        /// Folders holding links of `foldedCredits`, whose kinds `fold` records.
        let linkFolders: Set<Int32>

        init(table: DirectoryTable, options: ScanOptions) {
            self.table = table
            self.options = options
            let count = table.count
            var children = Array(repeating: [Int32](), count: count)
            var takes = table.ownTakesUp, newest = table.newestOwn
            for (folder, files) in table.largeFiles {
                for file in files {
                    takes[Int(folder)] += file.takesUp
                    newest[Int(folder)] = max(newest[Int(folder)], file.modified)
                }
            }
            // Children always have larger indices than their parent, so a reverse pass is a post-order:
            // first add up subtree totals, then decide what to keep from those totals.
            for index in stride(from: count - 1, to: 0, by: -1) where !table.excluded[index] {
                let parent = Int(table.parent[index])
                children[parent].append(Int32(index))
                takes[parent] += takes[index]
                newest[parent] = max(newest[parent], newest[index])
            }
            var keep = Array(repeating: false, count: count)
            for index in 0..<count where !table.excluded[index] {
                keep[index] = index == 0
                    || takes[index] >= options.minimumNodeSize.bytes   // the folder's TOTAL, not just its own files
                    || options.retainedDirectoryNames.contains(table.name[index])
                    || table.markers[Int32(index)] != nil
                    || table.largeFiles[Int32(index)] != nil
            }
            for index in stride(from: count - 1, to: 0, by: -1) where !table.excluded[index] && keep[index] {
                keep[Int(table.parent[index])] = true   // ancestors of kept folders are kept
            }
            // A link's private bytes count only in a node that holds all its links, and the smallest such
            // node gets them, so its total always includes the inode's takes-up.
            func nearestKept(_ folder: Int32) -> Int32 {
                var current = folder
                while !keep[Int(current)] { current = table.parent[Int(current)] }   // the root is always kept
                return current
            }
            var keptCredit: [Int32: UInt64] = [:], foldedCredits: [Int32: [DirectoryTable.LinkCredit]] = [:], linkFolders = Set<Int32>()
            for credit in table.linkCredits {
                let home = nearestKept(credit.commonAncestor)
                if credit.folders.allSatisfy({ !keep[Int($0)] && nearestKept($0) == home }) {
                    foldedCredits[home, default: []].append(credit)   // every link folds into `home`'s aggregates
                    linkFolders.formUnion(credit.folders)
                } else {
                    keptCredit[home, default: 0] += credit.freesAtLeast
                }
            }
            self.children = children
            totalTakesUp = takes
            newestTotal = newest
            self.keep = keep
            self.keptCredit = keptCredit
            self.foldedCredits = foldedCredits
            self.linkFolders = linkFolders
        }

        /// Int64.min is the table's "nothing dated here" value (APFS also clamps dates before 1677 to it).
        static func instant(_ nanoseconds: Int64) -> Instant? {
            nanoseconds == Int64.min ? nil : Instant(nanosecondsSince1970: nanoseconds)
        }

        func kind(of folder: Int32, path: CanonicalPath, parentKind: Kind?) -> Kind {
            options.classifier.kind(for: path, name: table.name[Int(folder)], markers: table.markers[folder] ?? [], parentKind: parentKind)
        }

        func draft(folder: Int32, path: CanonicalPath, parentKind: Kind?) -> NodeDraft {
            let index = Int(folder)
            let folderKind = kind(of: folder, path: path, parentKind: parentKind)
            var drafts: [(takes: UInt64, draft: NodeDraft)] = []
            var folded = FoldedTotals()
            var ownFrees = table.ownFreesAtLeast[index] + (keptCredit[folder] ?? 0)

            for child in children[index] {
                guard let childPath = path.appending(table.name[Int(child)]) else { continue }
                if keep[Int(child)] {
                    drafts.append((totalTakesUp[Int(child)], draft(folder: child, path: childPath, parentKind: folderKind)))
                } else {
                    fold(child, path: childPath, parentKind: folderKind, into: &folded)
                }
            }
            for credit in foldedCredits[folder] ?? [] {
                let kinds = Set(credit.folders.map { folded.kindOf[$0] })
                if kinds.count == 1, let kind = kinds.first ?? nil {
                    folded.byKind[kind, default: FoldedTotals.Total()].frees += credit.freesAtLeast   // one aggregate holds every link
                } else {
                    ownFrees += credit.freesAtLeast                                                   // the links fold into different kinds
                }
            }
            for file in table.largeFiles[folder] ?? [] {
                guard let filePath = path.appending(file.name) else { continue }
                let node = NodeDraft(
                    name: file.name, path: filePath, ownTakesUp: ByteCount(file.takesUp), ownFreesAtLeast: ByteCount(file.freesAtLeast),
                    newestChange: Self.instant(file.modified), markers: [], isFile: true, isAggregate: false,
                    aggregateKind: nil, children: []
                )
                drafts.append((file.takesUp, node))
            }
            for (aggregateKind, total) in folded.byKind where total.takes > 0 || total.frees > 0 {
                guard let aggregatePath = path.appending(".smaller-\(aggregateKind.rawValue)") else { continue }
                let node = NodeDraft(
                    name: total.count == 1 ? "1 smaller folder" : "\(total.count) smaller folders", path: aggregatePath,
                    ownTakesUp: ByteCount(total.takes), ownFreesAtLeast: ByteCount(total.frees),
                    newestChange: Self.instant(total.newest), markers: [], isFile: false, isAggregate: true,
                    aggregateKind: aggregateKind, children: []
                )
                drafts.append((total.takes, node))
            }
            drafts.sort { ($0.takes, $1.draft.name) > ($1.takes, $0.draft.name) }

            return NodeDraft(
                name: table.name[index], path: path,
                ownTakesUp: ByteCount(table.ownTakesUp[index]), ownFreesAtLeast: ByteCount(ownFrees),
                newestChange: Self.instant(newestTotal[index]), markers: table.markers[folder] ?? [],
                isFile: false, isAggregate: false, aggregateKind: nil, children: drafts.map(\.draft)
            )
        }

        /// Adds a folded subtree's own bytes to the per-kind totals, classifying every folder in it.
        /// A folder counts toward its kind's "n smaller folders" when it is a direct folded child or starts a new kind.
        func fold(_ top: Int32, path: CanonicalPath, parentKind: Kind, into totals: inout FoldedTotals) {
            var stack: [(folder: Int32, path: CanonicalPath, parentKind: Kind, isTop: Bool)] = [(top, path, parentKind, true)]
            while let (folder, folderPath, inherited, isTop) = stack.popLast() {
                let index = Int(folder)
                let folderKind = kind(of: folder, path: folderPath, parentKind: inherited)
                var entry = totals.byKind[folderKind] ?? FoldedTotals.Total()
                entry.takes += table.ownTakesUp[index]
                entry.frees += table.ownFreesAtLeast[index]
                entry.newest = max(entry.newest, table.newestOwn[index])
                for file in table.largeFiles[folder] ?? [] {
                    entry.takes += file.takesUp
                    entry.frees += file.freesAtLeast
                    entry.newest = max(entry.newest, file.modified)
                }
                if isTop || folderKind != inherited { entry.count += 1 }
                totals.byKind[folderKind] = entry
                if linkFolders.contains(folder) { totals.kindOf[folder] = folderKind }
                for child in children[index] {
                    guard let childPath = folderPath.appending(table.name[Int(child)]) else { continue }
                    stack.append((child, childPath, folderKind, false))
                }
            }
        }
    }

    struct FoldedTotals {
        struct Total {
            var takes: UInt64 = 0
            var frees: UInt64 = 0
            var newest: Int64 = Int64.min
            var count = 0
        }

        var byKind: [Kind: Total] = [:]
        /// The kinds of folded folders that hold hard links, for placing their credit.
        var kindOf: [Int32: Kind] = [:]
    }
}
