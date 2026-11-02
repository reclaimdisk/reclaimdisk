import Catalog
import SharedKernel

enum AgentAssembly {
    static func rules(home: CanonicalPath) -> [any Rule] {
        let layout = AgentHomeLayout.discover(home: home)
        let sessions = LiveSessionRecords(
            claude: ClaudeSessionReader(configDirectories: layout.claudeConfigs, tempRoot: layout.tempRoot),
            codex: CodexSessionReader(sessionsDirectory: layout.codexSessions), homeUnreadable: layout.homeUnreadable
        )
        return AgentRules.all(
            sessions: sessions, git: LiveGitRecords(), processes: LiveProcessRecords(), stale: LiveStaleBuildRecords()
        )
    }
}
