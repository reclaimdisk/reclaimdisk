import Application
import Foundation
import Inventory
import SharedKernel

/// Formats a Scan as JSON schema 1 or as plain text. Pure: no I/O.
enum ScanReport {
    // MARK: JSON schema 1

    static func json(_ scan: Scan) throws -> String {
        let disk = scan.disk
        let document: [String: Any] = [
            "schemaVersion": 1,
            "scope": scan.isWholeVolume ? "whole-volume" : "subtree",
            "volume": scan.volumeMountPath.raw,
            "startedAt": iso8601(scan.startedAt),
            "finishedAt": iso8601(scan.finishedAt),
            "disk": [
                "total": disk.data.total.bytes, "available": disk.data.available.bytes,
                "availableIncludingPurgeable": disk.data.availableIncludingPurgeable.bytes, "dataUsed": disk.data.usedByVolume.bytes,
                "swapUsed": disk.swapUsed.map { $0.bytes as Any } ?? NSNull(), "otherVolumesUsed": disk.otherVolumesUsed.bytes,
            ] as [String: Any],
            "scannedUniqueBytes": scan.scannedUniqueBytes.bytes,
            "notReadableBytes": scan.notReadable.map { $0.bytes as Any } ?? NSNull(),
            "needsFullDiskAccess": scan.needsFullDiskAccess,
            "unreadableAreas": scan.unreadable.map { ["path": $0.path.raw, "reason": $0.reason.rawValue] },
            "kinds": sortedKinds(scan).map { ["kind": $0.kind.rawValue, "takesUp": $0.total.takesUp.bytes, "freesAtLeast": $0.total.freesAtLeast.bytes] as [String: Any] },
            "root": node(scan.root),
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func node(_ node: Node) -> [String: Any] {
        [
            "name": node.name, "path": node.path.raw, "kind": node.kind.rawValue,
            "takesUp": node.footprint.takesUp.bytes, "freesAtLeast": node.footprint.freesAtLeast.bytes,
            "newestChange": node.newestChange.map { iso8601($0) as Any } ?? NSNull(), "isFile": node.isFile, "isAggregate": node.isAggregate,
            "markers": node.markers.sorted(), "children": node.children.map(Self.node),
        ]
    }

    private static func iso8601(_ instant: Instant) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: Double(instant.nanosecondsSince1970) / 1_000_000_000))
    }

    // MARK: text

    static func text(_ scan: Scan) -> String {
        var lines: [String] = []
        let data = scan.disk.data
        lines.append("Free: \(size(data.available)) of \(size(data.total))")
        if let notReadable = scan.notReadable, notReadable > .zero {
            lines.append("Not counted: \(size(notReadable)) (system-only folders, file-system metadata and snapshots)")
        }
        if scan.needsFullDiskAccess {
            lines.append("Some folders need Full Disk Access: open System Settings › Privacy & Security › Full Disk Access to include them.")
        }
        if scan.otherUnreadableCount > 0 {
            lines.append(UserMessages.unreadableFolders(count: scan.otherUnreadableCount) + " Run with --json to see which.")
        }
        lines.append("")
        let kinds = sortedKinds(scan)
        let titleWidth = max(4, kinds.map { KindTitles.title(for: $0.kind).count }.max() ?? 0)
        lines.append(pad("Kind", titleWidth) + "  " + leftPad("Takes up", 10) + "  " + leftPad("Frees at least", 14))
        for (kind, total) in kinds {
            lines.append(pad(KindTitles.title(for: kind), titleWidth) + "  " + leftPad(size(total.takesUp), 10)
                + "  " + leftPad(size(total.freesAtLeast, rounding: .down), 14))
        }
        let largest = largestFolders(scan.root)
        if !largest.isEmpty {
            lines.append("")
            lines.append("Largest folders")
            for node in largest {
                lines.append("  " + leftPad(size(node.footprint.takesUp), 10) + "  " + leftPad(size(node.footprint.freesAtLeast, rounding: .down), 10)
                    + "  " + DisplayText.escaped(node.path.raw))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The 10 largest kept, non-aggregate nodes whose children are each smaller than half of them.
    static func largestFolders(_ root: Node) -> [Node] {
        var found: [Node] = []
        var stack = root.children
        while let node = stack.popLast() {
            stack.append(contentsOf: node.children)
            guard !node.isAggregate else { continue }
            let half = node.footprint.takesUp.bytes / 2
            if node.children.allSatisfy({ $0.footprint.takesUp.bytes < half }) { found.append(node) }
        }
        return Array(found.sorted { ($0.footprint.takesUp, $1.path) > ($1.footprint.takesUp, $0.path) }.prefix(10))
    }

    private static func sortedKinds(_ scan: Scan) -> [(kind: Kind, total: KindTotal)] {
        scan.kindTotals().map { ($0.key, $0.value) }.sorted { ($0.total.takesUp, $1.kind.rawValue) > ($1.total.takesUp, $0.kind.rawValue) }
    }

    private static func size(_ bytes: ByteCount, rounding: ByteFormatting.Rounding = .nearest) -> String {
        ByteFormatting.string(bytes, rounding: rounding)
    }

    private static func pad(_ text: String, _ width: Int) -> String { text + String(repeating: " ", count: max(0, width - text.count)) }
    private static func leftPad(_ text: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - text.count)) + text }
}
