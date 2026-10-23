import Inventory
import SharedKernel

public struct DiskBarSegment: Equatable, Sendable {
    public enum Part: Hashable, Sendable { case kind(Kind), swap, otherVolumes, free }

    public let part: Part
    /// The segment's width in the bar. Kinds are scaled to fit the volume there, since copies sharing blocks count once.
    public let bytes: ByteCount
    /// The size the key shows: a kind's real takes-up, the same figure as the CLI and the map; otherwise `bytes`.
    public let shownBytes: ByteCount

    public init(part: Part, bytes: ByteCount, shownBytes: ByteCount? = nil) {
        self.part = part
        self.bytes = bytes
        self.shownBytes = shownBytes ?? bytes
    }
}

public enum DiskBarModel {
    /// Segment order: kinds by size descending (notReadable last among them), swap, otherVolumes, free.
    /// Kind bytes are scaled so kinds + notReadable == data.usedByVolume exactly (largest-remainder rounding).
    /// For subtree scans, returns only kind segments for the subtree, unscaled.
    public static func segments(for scan: Scan) -> [DiskBarSegment] {
        let kinds = scan.kindTotals()
            .filter { $0.value.takesUp > .zero }
            .map { (kind: $0.key, bytes: $0.value.takesUp.bytes) }
            .sorted { ($0.bytes, $1.kind.rawValue) > ($1.bytes, $0.kind.rawValue) }
        guard scan.isWholeVolume, let notReadable = scan.notReadable else {
            return kinds.map { DiskBarSegment(part: .kind($0.kind), bytes: ByteCount($0.bytes)) }
        }
        let used = scan.disk.data.usedByVolume.bytes
        var notCounted = notReadable.bytes
        var target = used - notCounted
        if kinds.isEmpty {   // nothing attributable: the whole used space is "not counted"
            notCounted = used
            target = 0
        }
        let scaled = scale(kinds.map(\.bytes), to: target)
        var segments = zip(kinds, scaled).map { DiskBarSegment(part: .kind($0.0.kind), bytes: ByteCount($0.1), shownBytes: ByteCount($0.0.bytes)) }
        if notCounted > 0 { segments.append(DiskBarSegment(part: .kind(.notReadable), bytes: ByteCount(notCounted))) }
        if let swap = scan.disk.swapUsed { segments.append(DiskBarSegment(part: .swap, bytes: swap)) }
        segments.append(DiskBarSegment(part: .otherVolumes, bytes: scan.disk.otherVolumesUsed))
        segments.append(DiskBarSegment(part: .free, bytes: scan.disk.data.available))
        return segments
    }

    /// Largest-remainder scaling: the result sums to exactly `target`. Uses 128-bit products, so no overflow.
    static func scale(_ values: [UInt64], to target: UInt64) -> [UInt64] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in 0 } }
        var shares: [(index: Int, quotient: UInt64, remainder: UInt64)] = values.enumerated().map { index, value in
            let product = value.multipliedFullWidth(by: target)
            let (quotient, remainder) = total.dividingFullWidth(product)
            return (index, quotient, remainder)
        }
        var leftover = target - shares.reduce(0) { $0 + $1.quotient }
        for position in shares.indices.sorted(by: { (shares[$0].remainder, -$0) > (shares[$1].remainder, -$1) }) where leftover > 0 {
            shares[position].quotient += 1
            leftover -= 1
        }
        return shares.sorted { $0.index < $1.index }.map(\.quotient)
    }
}
