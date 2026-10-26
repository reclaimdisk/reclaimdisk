import Inventory
import SharedKernel
import Testing

private let classifier = KindClassifier(home: CanonicalPath("/Users/u")!)
private func k(_ p: String, markers: Set<String> = [], parent: Kind? = nil) -> Kind {
    let path = CanonicalPath(p)!
    return classifier.kind(for: path, name: path.lastComponent, markers: markers, parentKind: parent)
}

@Test func classifierTable() {
    #expect(k("/Users/u/Movies/Demo.fcpbundle/x/Render Files", parent: .personalFiles) == .caches)          // the caches rule beats inheriting
    #expect(k("/Users/u/Movies/Demo.fcpbundle/x/Render Files/High Quality Media", parent: .caches) == .caches) // inheriting beats the personal-files rule
    #expect(k("/Users/u/Projects/app/.worktrees", parent: .projectSource) == .agentSessions)
    #expect(k("/Users/u/Projects/app/.worktrees/feat/svc", parent: .agentSessions) == .agentSessions)       // inheriting beats the project-source rule
    #expect(k("/Users/u/Projects/app/.worktrees/feat/svc/target", parent: .agentSessions) == .buildOutput)
    #expect(k("/private/tmp/claude-501", parent: .other) == .agentSessions)                               // the agent rule matches the third component
    #expect(k("/private/tmp/other-tool", parent: .other) == .other)
    #expect(k("/private/tmp/claude-501/p/s/scratchpad/fix3-target", markers: ["CACHEDIR.TAG", ".rustc_info.json"], parent: .agentSessions) == .buildOutput)
    #expect(k("/Users/u/Projects/app/retarget", parent: .projectSource) == .projectSource)                  // P3: no name pattern
    #expect(k("/Applications/Xcode.app", parent: .apps) == .developerTools)
    #expect(k("/Applications/Safari.app", parent: .apps) == .apps)
    #expect(k("/Users/u/Library/Containers/com.docker.docker/Data/vms", parent: .apps) == .docker)
    #expect(k("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/a.asset", parent: .macOSData) == .developerTools)
    #expect(k("/System/Library/AssetsV2/com_apple_MobileAsset_LinguisticData", parent: .macOSData) == .macOSData)
    #expect(k("/private/var/folders/fc", parent: .macOSData) == .caches)
    #expect(k("/private/var/db", parent: .other) == .macOSData)
    #expect(k("/Users/u/.claude-anthropic", parent: .other) == .agentSessions)
    #expect(k("/Users/u/Library", parent: .other) == .other)
    #expect(k("/Users/u/Library/Caches", parent: .other) == .caches)
    #expect(k("/Users/u", parent: nil) == .other)
    #expect(k("/Users/u/Projects/app", parent: .other) == .projectSource)
    #expect(k("/Users/u/Projects/app/src", parent: .projectSource) == .projectSource)
}

@Test func locationRulesCoverDevToolsPersonalAndApps() {
    #expect(k("/Users/u/.rustup", parent: .other) == .developerTools)
    #expect(k("/opt/homebrew", parent: .other) == .developerTools)
    #expect(k("/Library/Developer/CoreSimulator", parent: .other) == .developerTools)
    #expect(k("/Users/u/Downloads", parent: .other) == .personalFiles)
    #expect(k("/Users/u/Library/Application Support/Claude", parent: .other) == .apps)
    #expect(k("/Users/u/.docker", parent: .other) == .docker)
    #expect(k("/Users/u/Projects/app/.claude/worktrees/x", parent: .projectSource) == .agentSessions)
    #expect(k("/Users/u/Projects/app/node_modules", parent: .projectSource) == .buildOutput)
}

/// Build output keeps its kind all the way down, even inside caches and agent folders.
@Test func insideBuildOutputStaysBuildOutput() {
    #expect(k("/private/tmp/claude-501/s/proj/node_modules/left-pad", parent: .buildOutput) == .buildOutput)
    #expect(k("/Users/u/.claude/worktrees/w/target/debug", parent: .buildOutput) == .buildOutput)
    #expect(k("/Users/u/Library/Caches/tool/node_modules/x", parent: .buildOutput) == .buildOutput)
    #expect(k("/private/tmp/claude-501/s/node_modules/left-pad", parent: nil) == .buildOutput)   // a scan root inside build output
    #expect(k("/private/tmp/claude-501/s/app", parent: nil) == .agentSessions)
}
