import Catalog
import Inventory
import SharedKernel

/// The candidates and notes one pass over a scan produced.
public struct CandidateList: Sendable, Equatable {
    public let candidates: [Candidate]
    public let notes: [RuleNote]
    public let generatedAt: Instant

    public init(candidates: [Candidate], notes: [RuleNote], generatedAt: Instant) {
        self.candidates = candidates
        self.notes = notes
        self.generatedAt = generatedAt
    }
}

/// Runs the catalog rules over a finished scan. Path candidates inside personal folders are dropped
/// even when a rule emits one. A folder scan keeps only path candidates inside that folder. Nothing is deleted.
public struct ProposeCandidates: Sendable {
    private let rules: [any Rule]
    private let clock: any WallClock
    private let home: CanonicalPath

    public init(rules: [any Rule], clock: any WallClock, home: CanonicalPath) {
        self.rules = rules
        self.clock = clock
        self.home = home
    }

    public func callAsFunction(_ scan: Scan, kind: Kind? = nil) async -> CandidateList {
        let now = clock.now()
        let context = RuleContext(scan: ScanCatalogQuery(scan), home: home, now: now)
        let results: [RuleResult] = await Blocking.run {
            self.rules.map { $0.evaluate(context) }
        }
        var seen: Set<CandidateID> = []
        var candidates: [Candidate] = []
        for candidate in results.flatMap(\.candidates) {
            if case .path(let path) = candidate.target, PersonalLocations.contains(path, home: home) { continue }
            if !scan.isWholeVolume, !Self.isInside(candidate.target, root: scan.root.path) { continue }
            guard seen.insert(candidate.id).inserted else { continue }
            if let kind, candidate.kind != kind { continue }
            candidates.append(candidate)
        }
        candidates.sort(by: Self.comesFirst)
        return CandidateList(candidates: candidates, notes: results.flatMap(\.notes), generatedAt: now)
    }

    /// A folder run answers for that folder: a path elsewhere, or a tool resource, needs a run over the whole volume.
    private static func isInside(_ target: Target, root: CanonicalPath) -> Bool {
        guard case .path(let path) = target else { return false }
        return path.isSameOrDescendant(of: root)
    }

    /// Kind order, then the largest estimate, then the id.
    private static func comesFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let leftKind = Kind.allCases.firstIndex(of: lhs.kind) ?? 0
        let rightKind = Kind.allCases.firstIndex(of: rhs.kind) ?? 0
        if leftKind != rightKind { return leftKind < rightKind }
        let leftSize = lhs.estimate.freesAtLeast ?? lhs.estimate.reported ?? .zero
        let rightSize = rhs.estimate.freesAtLeast ?? rhs.estimate.reported ?? .zero
        if leftSize != rightSize { return leftSize > rightSize }
        return lhs.id < rhs.id
    }
}
