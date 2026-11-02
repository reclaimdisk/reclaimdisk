import Darwin
import Foundation

/// Runs one query and always returns. A child that ignores SIGKILL is kept alive in this process so releasing
/// `Process` cannot wait forever on a wedged Docker daemon.
enum ToolCacheCommand {
    struct Output: Sendable {
        var status: Int32
        var standardOutput: String
        var standardError: String
        var timedOut: Bool
    }

    static func run(
        executable: String, arguments: [String], environment: [String: String], timeout: Duration = .seconds(10)
    ) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        // Never the caller's folder: a project's own settings there (an `.npmrc`, say) would change what a tool reports.
        // The temporary folder is writable and on the Data volume; pnpm writes a probe file into its working folder.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory

        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = standardInput

        let outputFD = standardOutput.fileHandleForReading.fileDescriptor
        let errorFD = standardError.fileHandleForReading.fileDescriptor
        setNonBlocking(outputFD)
        setNonBlocking(errorFD)

        do { try process.run() } catch { return nil }
        // The child inherits the read end at run(); closing the write end gives it EOF instead of a prompt.
        try? standardInput.fileHandleForWriting.close()

        var output = Data()
        var errors = Data()
        let deadline = ContinuousClock.now + timeout
        var timedOut = false
        while process.isRunning {
            // Drain while the child runs. A full pipe would stall it, and waitUntilExit would then never return.
            drain(outputFD, into: &output)
            drain(errorFD, into: &errors)
            if ContinuousClock.now >= deadline {
                if process.isRunning {
                    timedOut = true
                    kill(process.processIdentifier, SIGKILL)
                    let killDeadline = ContinuousClock.now + .seconds(1)
                    while process.isRunning, ContinuousClock.now < killDeadline {
                        drain(outputFD, into: &output)
                        drain(errorFD, into: &errors)
                        usleep(20_000)
                    }
                }
                break
            }
            usleep(20_000)
        }
        drain(outputFD, into: &output)
        drain(errorFD, into: &errors)

        if process.isRunning {
            StuckChildren.shared.keep(process)
            return Output(status: -1, standardOutput: decode(output), standardError: decode(errors), timedOut: true)
        }
        return Output(
            status: process.terminationStatus, standardOutput: decode(output), standardError: decode(errors), timedOut: timedOut
        )
    }

    /// The first executable file named `name` in `directories`. Symlinks are followed; directories are not accepted.
    static func executable(named name: String, in directories: [String]) -> String? {
        for directory in directories {
            let path = directory + "/" + name
            guard access(path, X_OK) == 0 else { continue }
            let fd = open(path, O_RDONLY)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            return path
        }
        return nil
    }
}

private final class StuckChildren: @unchecked Sendable {
    static let shared = StuckChildren()
    private let lock = NSLock()
    private var processes: [Process] = []

    func keep(_ process: Process) {
        lock.lock()
        processes.append(process)
        lock.unlock()
    }
}

private func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0 else { return }
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
}

/// Returns false once the pipe has reached EOF.
@discardableResult
private func drain(_ fd: Int32, into data: inout Data) -> Bool {
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count > 0 {
            data.append(contentsOf: buffer.prefix(count))
            continue
        }
        if count == 0 { return false }
        if errno == EINTR { continue }
        return true
    }
}

private func decode(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
}
