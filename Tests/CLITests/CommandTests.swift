import Application
import Testing
@testable import CLI

@Test func versionFlagPrintsTheProductVersion() {
    do {
        _ = try ReclaimDiskCommand.parseAsRoot(["--version"])
        Issue.record("--version should end parsing with a clean exit")
    } catch {
        #expect(ReclaimDiskCommand.exitCode(for: error).isSuccess)
        #expect(ReclaimDiskCommand.fullMessage(for: error) == ProductInfo.version)
    }
}
