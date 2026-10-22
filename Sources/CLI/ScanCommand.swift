import Application
import ArgumentParser
import Darwin
import Foundation
import Infrastructure
import Inventory
import SharedKernel

/// A user-facing failure whose message is already final (printed as "reclaimdisk: <message>", exit 1).
struct CLIFailure: Error, Equatable {
    let message: String
}

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Show where the space on the Data volume (or one folder) goes."
    )

    @Option(name: .long, help: "A folder to scan instead of the whole Data volume. Relative paths, '.', '..' and symlinks are resolved.")
    var path: String?

    @Flag(name: .long, help: "Print JSON (schema 1) instead of text.")
    var json = false

    func run() async throws {
        let reader = DarwinVolumeReader()
        let runScan = RunScan(reader: reader, clock: SystemWallClock(), home: PathResolver.homeDirectory())
        var request = ScanRequest()
        if let input = path {
            let current = (try? PathResolver.resolve(FileManager.default.currentDirectoryPath, currentDirectory: .root)) ?? .root
            let resolved = try Self.resolvePath(input, currentDirectory: current)
            if resolved.raw != input { Self.standardError("Scanning \(resolved.raw) (resolved from \(input))\n") }
            request.path = resolved
        }
        if let layout = try? runScan.preflight(), layout.data.available < RunScan.lowDiskThreshold {
            let free = ByteFormatting.string(layout.data.available, rounding: .down)
            Self.standardError("\(ProductInfo.commandName): \(UserMessages.lowDiskWarning(available: layout.data.available, formatted: free))\n")
        }
        let showProgress = isatty(STDERR_FILENO) == 1
        let scan = try await runScan(request) { progress in
            guard showProgress else { return }
            let bytes = ByteFormatting.string(progress.bytesSeen, rounding: .nearest)
            Self.standardError("\rRead \(ByteFormatting.grouped(progress.directoriesRead)) folders, \(bytes)…")
        }
        if showProgress { Self.standardError("\r\u{1B}[K") }
        print(json ? try ScanReport.json(scan) : ScanReport.text(scan))
    }

    /// Resolves `--path` (relative, ".", "..", symlinks); "/" is refused in favor of the whole-volume default.
    static func resolvePath(_ input: String, currentDirectory: CanonicalPath) throws -> CanonicalPath {
        let resolved: CanonicalPath
        do {
            resolved = try PathResolver.resolve(input, currentDirectory: currentDirectory)
        } catch {
            throw CLIFailure(message: UserMessages.text(forUnresolvablePath: input, error: error))
        }
        guard resolved != .root else { throw CLIFailure(message: "omit --path to scan the whole Data volume.") }
        return resolved
    }

    static func standardError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
