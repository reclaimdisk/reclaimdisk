import Application
import Infrastructure
import Inventory
import Observation
import SharedKernel

@MainActor @Observable
public final class ScanModel {
    public enum State: Equatable {
        case idle(lowDiskWarning: String?)
        case scanning(ScanProgress)
        case finished(Scan)
        case failed(message: String)
    }

    public private(set) var state: State
    public private(set) var lastRequest = ScanRequest()

    private let runScan: RunScan
    private var task: Task<Void, Never>?
    /// Bumped on every start and cancel, so a stale scan can never write its result.
    private var generation = 0

    public init(runScan: RunScan) {
        self.runScan = runScan
        state = .idle(lowDiskWarning: Self.lowDiskWarning(runScan))
    }

    /// The model wired to the real disk.
    public static func live() -> ScanModel {
        ScanModel(runScan: RunScan(reader: DarwinVolumeReader(), clock: SystemWallClock(), home: PathResolver.homeDirectory()))
    }

    public func start(_ request: ScanRequest = ScanRequest()) {
        task?.cancel()
        generation += 1
        let current = generation
        lastRequest = request
        state = .scanning(ScanProgress(directoriesRead: 0, bytesSeen: .zero, currentPath: nil))
        let runScan = runScan
        // The task holds the model only for the length of one scan.
        task = Task {
            do {
                let scan = try await runScan(request) { progress in
                    Task { @MainActor in self.showProgress(progress, generation: current) }
                }
                guard generation == current else { return }
                state = .finished(scan)
            } catch {
                guard generation == current else { return }
                state = error is CancellationError
                    ? .idle(lowDiskWarning: Self.lowDiskWarning(runScan))
                    : .failed(message: UserMessages.text(for: error))
            }
        }
    }

    private func showProgress(_ progress: ScanProgress, generation expected: Int) {
        guard generation == expected, case .scanning = state else { return }
        state = .scanning(progress)
    }

    /// Returns to idle at once; the running scan stops and its result is dropped.
    public func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        state = .idle(lowDiskWarning: Self.lowDiskWarning(runScan))
    }

    private static func lowDiskWarning(_ runScan: RunScan) -> String? {
        guard let layout = try? runScan.preflight(), layout.data.available < RunScan.lowDiskThreshold else { return nil }
        let available = layout.data.available
        return UserMessages.lowDiskWarning(available: available, formatted: ByteFormatting.string(available, rounding: .down))
    }
}
