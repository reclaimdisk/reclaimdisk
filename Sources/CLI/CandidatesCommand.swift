import Application
import ArgumentParser
import Darwin
import Foundation
import Infrastructure
import SharedKernel

/// Lists cleanup candidates for one folder or the whole Data volume. It never deletes anything.
struct CandidatesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "candidates",
        abstract: "List cleanup candidates for the Data volume or one folder. Nothing is deleted."
    )

    @Option(name: .long, help: "A folder to scan instead of the whole Data volume. Relative paths, '.', '..' and symlinks are resolved.")
    var path: String?

    @Option(name: .long, help: "Only candidates of this kind, for example build-output or caches.")
    var kind: Kind?

    @Flag(name: .long, help: "Print JSON (schema 1) instead of text.")
    var json = false

    func run() async throws {
        let reader = DarwinVolumeReader()
        let home = PathResolver.homeDirectory()
        let clock = SystemWallClock()
        let runScan = RunScan(reader: reader, clock: clock, home: home)
        var request = ScanRequest()
        if let input = path {
            let current = (try? PathResolver.resolve(FileManager.default.currentDirectoryPath, currentDirectory: .root)) ?? .root
            let resolved = try ScanCommand.resolvePath(input, currentDirectory: current)
            if resolved.raw != input { ScanCommand.standardError("Scanning \(resolved.raw) (resolved from \(input))\n") }
            request.path = resolved
        }
        if let layout = try? runScan.preflight(), layout.data.available < RunScan.lowDiskThreshold {
            let free = ByteFormatting.string(layout.data.available, rounding: .down)
            ScanCommand.standardError("\(ProductInfo.commandName): \(UserMessages.lowDiskWarning(available: layout.data.available, formatted: free))\n")
        }
        let showProgress = isatty(STDERR_FILENO) == 1
        let scan = try await runScan(request) { progress in
            guard showProgress else { return }
            let bytes = ByteFormatting.string(progress.bytesSeen, rounding: .nearest)
            ScanCommand.standardError("\rRead \(ByteFormatting.grouped(progress.directoriesRead)) folders, \(bytes)…")
        }
        if showProgress { ScanCommand.standardError("\r\u{1B}[K") }
        let list = await ProposeCandidates(rules: LiveCatalog.rules(home: home), clock: clock, home: home)(scan, kind: kind)
        let scanRoot = DisplayPath.forReadPath(request.path ?? RunScan.dataVolume)
        print(json ? try CandidateReport.json(list, scanRoot: scanRoot) : CandidateReport.text(list))
    }
}
