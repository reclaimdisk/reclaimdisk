import Dispatch

/// Runs one blocking call off Swift's cooperative thread pool (Global Constraints; see ReadPool).
enum Blocking {
    private static let queue = DispatchQueue(label: "reclaimdisk.blocking", qos: .userInitiated, attributes: .concurrent)

    static func run<T: Sendable, E: Error>(_ work: @escaping @Sendable () throws(E) -> T) async throws(E) -> T {
        let result: Result<T, E> = await withCheckedContinuation { continuation in
            queue.async {
                do throws(E) { continuation.resume(returning: .success(try work())) } catch { continuation.resume(returning: .failure(error)) }
            }
        }
        return try result.get()
    }
}
