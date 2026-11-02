import Application
import Infrastructure
import Inventory
import Observation
import SharedKernel

/// Turns one finished scan into a candidate list. Nothing is deleted.
@MainActor @Observable
public final class CandidatesModel {
    public enum State: Equatable {
        case idle
        case proposing
        case ready(CandidateList)
        case failed(message: String)
    }

    public private(set) var state: State

    private let makePropose: @Sendable () -> ProposeCandidates
    private var task: Task<Void, Never>?
    /// Bumped on every propose, so a pass that lost the race never writes its list.
    private var generation = 0

    public convenience init(propose: ProposeCandidates) {
        self.init(makePropose: { propose })
    }

    public init(makePropose: @escaping @Sendable () -> ProposeCandidates) {
        self.makePropose = makePropose
        state = .idle
    }

    /// The model wired to the real catalog. Each pass builds its own proposer: the live record readers
    /// keep the first reading they make, so a later pass must not reuse them.
    public static func live() -> CandidatesModel {
        let home = PathResolver.homeDirectory()
        return CandidatesModel(makePropose: {
            ProposeCandidates(rules: LiveCatalog.rules(home: home), clock: SystemWallClock(), home: home)
        })
    }

    /// Cancels a proposal already running, then starts one for `scan`.
    public func propose(from scan: Scan) {
        task?.cancel()
        generation += 1
        let current = generation
        state = .proposing
        let makePropose = makePropose
        task = Task {
            let propose = makePropose()
            let list = await propose(scan)
            guard generation == current else { return }
            state = .ready(list)
        }
    }
}
