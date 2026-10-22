import Application
import ArgumentParser
import Darwin
import Foundation

@main
struct ReclaimDiskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: ProductInfo.commandName,
        abstract: "See where your Mac's disk space goes and reclaim it safely.",
        subcommands: [ScanCommand.self]
    )

    /// Spec 11.2 wants exit 1 for usage errors; swift-argument-parser would exit 64 (EX_USAGE), so main is ours.
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let error as ScanError {
            fail(UserMessages.text(for: error))
        } catch let error as CLIFailure {
            fail(error.message)
        } catch is CancellationError {
            fail(UserMessages.text(for: CancellationError()))
        } catch {
            if exitCode(for: error).isSuccess {   // --help, --version
                print(fullMessage(for: error))
                Darwin.exit(0)
            }
            FileHandle.standardError.write(Data((fullMessage(for: error) + "\n").utf8))
            Darwin.exit(1)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(ProductInfo.commandName): \(message)\n".utf8))
        Darwin.exit(1)
    }
}
