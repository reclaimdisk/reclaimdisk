import SharedKernel

/// Sessions an agent tool has already recorded. Reading them does not start or stop a session.
public protocol SessionRecords: Sendable {
    func sessions() -> SessionReading
}

public enum SessionReading: Sendable, Equatable {
    case read([AgentSession])
    case unreadable(String)
}

public struct AgentSession: Sendable, Equatable {
    public var tool: String
    public var id: String
    public var lastActivity: Instant
    public var workingDirectories: Set<CanonicalPath>
    public var tempFolder: CanonicalPath?

    public init(
        tool: String, id: String, lastActivity: Instant, workingDirectories: Set<CanonicalPath>, tempFolder: CanonicalPath?
    ) {
        self.tool = tool
        self.id = id
        self.lastActivity = lastActivity
        self.workingDirectories = workingDirectories
        self.tempFolder = tempFolder
    }
}

/// What Git can say about a folder. Asking does not add, remove or prune a worktree.
public protocol GitRecords: Sendable {
    func worktree(at path: CanonicalPath) -> WorktreeReading
    func isIgnored(_ path: CanonicalPath) -> Bool?
}

public enum WorktreeReading: Sendable, Equatable {
    case notAWorktree
    case unreadable(String)
    case worktree(WorktreeState)
}

public struct WorktreeState: Sendable, Equatable {
    public var branch: String?
    public var mainRepository: CanonicalPath
    public var hasChanges: Bool
    public var ignoredNonBuildPaths: [String]
    public var hasSubmodules: Bool
    public var isLocked: Bool

    public init(
        branch: String?, mainRepository: CanonicalPath, hasChanges: Bool, ignoredNonBuildPaths: [String],
        hasSubmodules: Bool, isLocked: Bool
    ) {
        self.branch = branch
        self.mainRepository = mainRepository
        self.hasChanges = hasChanges
        self.ignoredNonBuildPaths = ignoredNonBuildPaths
        self.hasSubmodules = hasSubmodules
        self.isLocked = isLocked
    }
}

/// Processes that are running now, so a rule can see whether a checkout is still in use.
public protocol ProcessRecords: Sendable {
    func processes() -> ProcessReading
}

public enum ProcessReading: Sendable, Equatable {
    case read([RunningProcess])
    case unreadable(String)
}

public struct RunningProcess: Sendable, Equatable {
    public var name: String
    public var workingDirectory: CanonicalPath?

    public init(name: String, workingDirectory: CanonicalPath?) {
        self.name = name
        self.workingDirectory = workingDirectory
    }
}

/// How much of a Rust build folder has sat untouched. Counting does not delete anything.
public protocol StaleBuildRecords: Sendable {
    func stale(in target: CanonicalPath, untouchedForSeconds: Int64, now: Instant) -> StaleReading
}

public enum StaleReading: Sendable, Equatable {
    case read(entries: Int, takesUp: ByteCount, freesAtLeast: ByteCount)
    case unreadable(String)
}
