@testable import Infrastructure
import Testing

/// A wedged tool (Docker hangs while the disk is full) must never hang a scan: the query stops at its timeout.
@Test func aCommandThatHangsIsStoppedAtItsTimeout() {
    let start = ContinuousClock.now
    let output = ToolCacheCommand.run(executable: "/bin/sleep", arguments: ["30"], environment: [:], timeout: .milliseconds(300))
    #expect(output?.timedOut == true)
    #expect(ContinuousClock.now - start < .seconds(5))
}

/// A tool that prints more than a pipe holds must not stall waiting for a reader.
@Test func aCommandWithLongOutputFinishesWithAllOfIt() {
    let output = ToolCacheCommand.run(
        executable: "/bin/sh", arguments: ["-c", "yes x | head -c 1000000"], environment: ["PATH": "/usr/bin:/bin"], timeout: .seconds(10)
    )
    #expect(output?.timedOut == false)
    #expect(output?.status == 0)
    #expect(output?.standardOutput.count == 1_000_000)
}

/// A query never inherits the caller's folder, so a project's own tool settings (an `.npmrc` beside the shell) can't
/// redirect what a tool reports.
@Test func aCommandRunsFromTheRootFolder() {
    let output = ToolCacheCommand.run(executable: "/bin/pwd", arguments: [], environment: [:], timeout: .seconds(10))
    #expect(output?.standardOutput == "/\n")
}
