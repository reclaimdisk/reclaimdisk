import Catalog
import Darwin
import Foundation
import SharedKernel

/// Claude Code transcripts under `<config>/projects/<project>/<id>.jsonl`.
struct ClaudeSessionReader {
    var configDirectories: [URL]
    var tempRoot: CanonicalPath

    /// Working directories are collected only while the transcript may still be live. Older sessions stay in the
    /// result, with an empty set, so a finished session cannot mark a checkout as in use.
    func read(now: Instant, activityWindowSeconds: Int64) -> [AgentSession]? {
        var sessions: [AgentSession] = []
        for config in configDirectories {
            let projects = config.appendingPathComponent("projects", isDirectory: true)
            let projectURLs: [URL]
            do {
                projectURLs = try FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
            } catch {
                return nil
            }
            for projectURL in projectURLs {
                guard FileKind.isDirectory(projectURL) else { continue }
                let files: [URL]
                do {
                    files = try FileManager.default.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil)
                } catch {
                    return nil
                }
                for file in files where file.pathExtension == "jsonl" {
                    switch FileKind.kind(file) {
                    case .file: break
                    case .unreadable: return nil
                    case .directory, .other: continue
                    }
                    guard let modified = FileKind.modified(file) else { return nil }
                    let recent = ActivityWindow.contains(modified, now: now, windowSeconds: activityWindowSeconds)
                    let directories: Set<CanonicalPath>
                    if recent {
                        guard let found = WorkingDirectories.claude(in: file) else { return nil }
                        directories = found
                    } else {
                        directories = []
                    }
                    let id = file.deletingPathExtension().lastPathComponent
                    let project = projectURL.lastPathComponent
                    sessions.append(AgentSession(
                        tool: "claude", id: id, lastActivity: modified, workingDirectories: directories,
                        tempFolder: tempRoot.appending(project)?.appending(id)
                    ))
                }
            }
        }
        return sessions
    }
}

/// Codex rollout transcripts. The session id and working directory come from the first `session_meta` line.
struct CodexSessionReader {
    var sessionsDirectory: URL

    func read(now: Instant, activityWindowSeconds: Int64) -> [AgentSession]? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return nil }
        return sessions(in: sessionsDirectory, now: now, activityWindowSeconds: activityWindowSeconds)
    }

    /// A directory that cannot be listed fails the whole read, so a live rollout is not mistaken for a missing one.
    private func sessions(in directory: URL, now: Instant, activityWindowSeconds: Int64) -> [AgentSession]? {
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch { return nil }
        var sessions: [AgentSession] = []
        for child in children {
            switch FileKind.kind(child) {
            case .unreadable: return nil
            case .directory:
                guard let nested = self.sessions(in: child, now: now, activityWindowSeconds: activityWindowSeconds) else { return nil }
                sessions.append(contentsOf: nested)
            case .other: continue
            case .file:
                let name = child.lastPathComponent
                guard name.hasPrefix("rollout-"), child.pathExtension == "jsonl" else { continue }
                guard let modified = FileKind.modified(child) else { return nil }
                switch WorkingDirectories.codexMeta(in: child) {
                case .failed: return nil
                case .none: continue
                case .meta(let id, let cwd):
                    let recent = ActivityWindow.contains(modified, now: now, windowSeconds: activityWindowSeconds)
                    sessions.append(AgentSession(
                        tool: "codex", id: id, lastActivity: modified,
                        workingDirectories: recent ? cwd.map { [$0] } ?? [] : [], tempFolder: nil
                    ))
                }
            }
        }
        return sessions
    }
}

/// Claude and Codex together. A home folder that cannot be listed is unreadable, so a rule will not treat those
/// sessions as finished.
final class LiveSessionRecords: SessionRecords, @unchecked Sendable {
    private let claude: ClaudeSessionReader
    private let codex: CodexSessionReader
    private let homeUnreadable: Bool
    private let lock = NSLock()
    private var cached: SessionReading?

    init(claude: ClaudeSessionReader, codex: CodexSessionReader, homeUnreadable: Bool) {
        self.claude = claude
        self.codex = codex
        self.homeUnreadable = homeUnreadable
    }

    func sessions() -> SessionReading {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let reading = load()
        cached = reading
        return reading
    }

    private func load() -> SessionReading {
        if homeUnreadable { return .unreadable("Can't read the home folder.") }
        let now = SystemWallClock().now()
        let window = RecentActivity.windowSeconds
        guard let claudeSessions = claude.read(now: now, activityWindowSeconds: window) else {
            return .unreadable("Can't read Claude session transcripts.")
        }
        guard let codexSessions = codex.read(now: now, activityWindowSeconds: window) else {
            return .unreadable("Can't read Codex session transcripts.")
        }
        return .read(claudeSessions + codexSessions)
    }
}

enum AgentHomeLayout {
    struct Layout {
        var claudeConfigs: [URL]
        var codexSessions: URL
        var tempRoot: CanonicalPath
        var homeUnreadable: Bool
    }

    /// Every `~/.claude*` directory that holds `projects`, plus the Codex session directory and the temp root.
    static func discover(home: CanonicalPath) -> Layout {
        let homeURL = URL(fileURLWithPath: home.raw, isDirectory: true)
        let codex = homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        let tempRoot = CanonicalPath("/private/tmp/claude-\(getuid())") ?? CanonicalPath("/private/tmp")!
        do {
            let entries = try FileManager.default.contentsOfDirectory(at: homeURL, includingPropertiesForKeys: nil)
            let configs = entries.filter { url in
                let name = url.lastPathComponent
                guard name.hasPrefix(".claude"), FileKind.isDirectory(url) else { return false }
                return FileKind.isDirectory(url.appendingPathComponent("projects", isDirectory: true))
            }
            return Layout(claudeConfigs: configs, codexSessions: codex, tempRoot: tempRoot, homeUnreadable: false)
        } catch {
            return Layout(claudeConfigs: [], codexSessions: codex, tempRoot: tempRoot, homeUnreadable: true)
        }
    }
}

private enum ActivityWindow {
    static func contains(_ instant: Instant, now: Instant, windowSeconds: Int64) -> Bool {
        let (window, overflowed) = windowSeconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflowed else { return false }
        let (age, ageOverflowed) = now.nanosecondsSince1970.subtractingReportingOverflow(instant.nanosecondsSince1970)
        if ageOverflowed { return instant > now }
        return age < window
    }
}

private enum FileKind {
    enum Kind { case directory, file, other, unreadable }

    static func kind(_ url: URL) -> Kind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .unreadable }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFREG: return .file
        default: return .other
        }
    }

    static func isDirectory(_ url: URL) -> Bool { kind(url) == .directory }

    static func modified(_ url: URL) -> Instant? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Instant(seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
    }
}

private enum CodexMeta {
    case meta(id: String, cwd: CanonicalPath?)
    case none
    case failed
}

private enum WorkingDirectories {
    /// Claude Code writes compact JSON lines with the working directory under a `"cwd"` key, and transcripts reach
    /// hundreds of megabytes, so the file is searched for that key instead of decoding every line. Only distinct values
    /// are decoded. A key quoted inside a message is escaped (`\"cwd\"`) and does not match; a key in a nested object
    /// does, which can only mark more folders as in use.
    static func claude(in file: URL) -> Set<CanonicalPath>? {
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { return nil }
        let key = Array(#""cwd":""#.utf8)
        var values: Set<Data> = []
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count, let found = memmem(base + offset, buffer.count - offset, key, key.count) {
                let keyStart = base.distance(to: UnsafeRawPointer(found))
                let valueStart = keyStart + key.count
                offset = valueStart
                let before = keyStart > 0 ? buffer[keyStart - 1] : UInt8(ascii: "{")
                guard before == UInt8(ascii: "{") || before == UInt8(ascii: ",") else { continue }
                guard let valueEnd = closingQuote(in: buffer, from: valueStart) else { continue }
                values.insert(Data(buffer[(valueStart - 1)...valueEnd]))
                offset = valueEnd + 1
            }
        }
        var directories: Set<CanonicalPath> = []
        for value in values {
            guard let text = try? JSONSerialization.jsonObject(with: value, options: .fragmentsAllowed) as? String,
                  let path = CanonicalPath(text) else { continue }
            directories.insert(path)
        }
        return directories
    }

    /// The first `session_meta` line names the session; the rest of the rollout is never decoded.
    static func codexMeta(in file: URL) -> CodexMeta {
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { return .failed }
        var meta = CodexMeta.none
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            while start < buffer.count {
                let end = memchr(base + start, 10, buffer.count - start).map { base.distance(to: UnsafeRawPointer($0)) } ?? buffer.count
                var line = Data(buffer[start..<end])
                if line.last == 13 { line.removeLast() }
                start = end + 1
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["type"] as? String == "session_meta",
                      let payload = object["payload"] as? [String: Any], let id = payload["id"] as? String, !id.isEmpty else {
                    continue
                }
                meta = .meta(id: id, cwd: (payload["cwd"] as? String).flatMap(CanonicalPath.init))
                return
            }
        }
        return meta
    }

    /// The index of the quote that ends a JSON string starting at `start`, or nil when the line ends first.
    private static func closingQuote(in buffer: UnsafeRawBufferPointer, from start: Int) -> Int? {
        var index = start
        var escaped = false
        while index < buffer.count {
            let byte = buffer[index]
            if escaped {
                escaped = false
            } else if byte == UInt8(ascii: "\\") {
                escaped = true
            } else if byte == UInt8(ascii: "\"") {
                return index
            } else if byte == 10 {
                return nil
            }
            index += 1
        }
        return nil
    }
}
