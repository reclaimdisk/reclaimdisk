import ArgumentParser

@main
struct ReclaimDiskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reclaimdisk",
        abstract: "See where your Mac's disk space goes and reclaim it safely."
    )
}
