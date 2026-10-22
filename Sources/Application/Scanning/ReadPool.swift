import Dispatch
import SharedKernel

/// Runs blocking file-system calls on a private concurrent queue, never on Swift's cooperative thread pool:
/// blocking those threads starves other tasks (WWDC21 "Swift concurrency: Behind the scenes",
/// https://developer.apple.com/videos/play/wwdc2021/10254/). Callers bound how many calls are in flight.
/// This is the only place that calls `VolumeReader.readDirectory` during a scan.
struct ReadPool: Sendable {
    private let reader: any VolumeReader
    private let queue = DispatchQueue(label: "reclaimdisk.read-pool", qos: .userInitiated, attributes: .concurrent)

    init(reader: any VolumeReader) { self.reader = reader }

    func readDirectory(at path: CanonicalPath) async -> Result<[DirectoryEntry], DirectoryReadError> {
        let reader = reader
        return await withCheckedContinuation { continuation in
            queue.async {
                do throws(DirectoryReadError) { continuation.resume(returning: .success(try reader.readDirectory(at: path))) } catch { continuation.resume(returning: .failure(error)) }
            }
        }
    }

    func deviceID(of path: CanonicalPath) async -> Result<Int32, DirectoryReadError> {
        let reader = reader
        return await withCheckedContinuation { continuation in
            queue.async {
                do throws(DirectoryReadError) { continuation.resume(returning: .success(try reader.deviceID(of: path))) } catch { continuation.resume(returning: .failure(error)) }
            }
        }
    }
}
