import Application
import Catalog
import SharedKernel

/// One kind's candidates, in the order the list gave them, and what the preselected ones free at least.
struct CandidateGroup: Equatable {
    let kind: Kind
    let title: String
    let candidates: [Candidate]
    let selectedByDefaultFreesAtLeast: ByteCount
}

/// Groups a candidate list by kind. Empty kinds are left out. Nothing is reordered inside a kind.
enum CandidateGroups {
    static func make(_ list: CandidateList) -> [CandidateGroup] {
        let grouped = Dictionary(grouping: list.candidates, by: \.kind)
        return Kind.allCases.compactMap { kind in
            guard let candidates = grouped[kind], !candidates.isEmpty else { return nil }
            return CandidateGroup(
                kind: kind, title: KindTitles.title(for: kind), candidates: candidates,
                selectedByDefaultFreesAtLeast: freesAtLeast(candidates)
            )
        }
    }

    static func selectedByDefaultFreesAtLeast(_ list: CandidateList) -> ByteCount {
        freesAtLeast(list.candidates)
    }

    static func selectedByDefaultCount(_ list: CandidateList) -> Int {
        list.candidates.reduce(0) { count, candidate in count + (candidate.isPreselected ? 1 : 0) }
    }

    /// Only a preselected candidate contributes, and only its measured lower bound.
    private static func freesAtLeast(_ candidates: [Candidate]) -> ByteCount {
        candidates.reduce(.zero) { sum, candidate in
            guard candidate.isPreselected, let frees = candidate.estimate.freesAtLeast else { return sum }
            return sum + frees
        }
    }
}
