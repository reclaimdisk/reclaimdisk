import Catalog
import Darwin
import Foundation
import SharedKernel

/// Reads linked worktrees and ignore rules. The only Git commands are rev-parse, status and check-ignore.
/// Optional locks are turned off so `status` does not refresh the index.
struct LiveGitRecords: GitRecords {
    private static let git = "/usr/bin/git"
    private static let timeoutSeconds = 10
    private static let buildOutputNames: Set<String> = [
        "target", "build", "dist", "out", "node_modules", ".next", ".turbo", ".parcel-cache", ".svelte-kit", ".nuxt",
        ".venv", "venv", ".gradle", "DerivedData", "__pycache__", ".build",
    ]

    func worktree(at path: CanonicalPath) -> WorktreeReading {
        switch dotGit(at: path) {
        case .absent, .directory: return .notAWorktree
        case .file: break
        }
        guard let parsed = run([
            "--no-optional-locks", "-C", path.raw, "rev-parse", "--path-format=absolute", "--abbrev-ref", "HEAD",
            "--git-common-dir", "--git-dir",
        ]), parsed.status == 0 else {
            return .unreadable("Can't read the worktree from Git.")
        }
        let lines = parsed.output.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard lines.count >= 3,
              let common = canonical(lines[1], relativeTo: path),
              let main = mainRepository(common: common, worktree: path),
              let gitDir = canonical(lines[2], relativeTo: path) else {
            return .unreadable("Can't read the worktree from Git.")
        }
        guard let status = run([
            "--no-optional-locks", "-C", path.raw, "status", "--porcelain", "--ignored", "--untracked-files=normal",
        ]), status.status == 0 else {
            return .unreadable("Can't read the worktree from Git.")
        }
        let changes = StatusSummary.parse(status.output, buildOutputNames: Self.buildOutputNames)
        // A detached HEAD prints "HEAD": that is no branch.
        let branch = lines[0].isEmpty || lines[0] == "HEAD" ? nil : lines[0]
        let submodules = FileManager.default.fileExists(atPath: path.raw + "/.gitmodules")
        let locked = FileManager.default.fileExists(atPath: gitDir.raw + "/locked")
        return .worktree(WorktreeState(
            branch: branch, mainRepository: main, hasChanges: changes.hasChanges,
            ignoredNonBuildPaths: changes.ignoredNonBuildPaths, hasSubmodules: submodules, isLocked: locked
        ))
    }

    func isIgnored(_ path: CanonicalPath) -> Bool? {
        let directory = path.parent ?? .root
        guard let result = run(["--no-optional-locks", "-C", directory.raw, "check-ignore", "-q", "--", path.raw]) else {
            return nil
        }
        switch result.status {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    private enum DotGit { case absent, directory, file }

    private func dotGit(at path: CanonicalPath) -> DotGit {
        var info = stat()
        let git = path.raw + "/.git"
        guard lstat(git, &info) == 0 else { return .absent }
        return info.st_mode & S_IFMT == S_IFDIR ? .directory : .file
    }

    /// Git reports the real path (`/private/var`), while a caller may have spelled the same folder `/var`.
    /// When the worktree still lives inside the main repository, keep the caller's spelling so the two paths compare equal.
    private func mainRepository(common: CanonicalPath, worktree: CanonicalPath) -> CanonicalPath? {
        guard let resolvedCommon = realPath(common), let resolvedMain = resolvedCommon.parent else { return common.parent }
        guard let resolvedWorktree = realPath(worktree), resolvedWorktree.isSameOrDescendant(of: resolvedMain) else {
            return resolvedMain
        }
        let extra = resolvedWorktree.components.count - resolvedMain.components.count
        guard extra <= worktree.components.count else { return resolvedMain }
        let kept = worktree.components.dropLast(extra)
        let raw = kept.isEmpty ? "/" : "/" + kept.joined(separator: "/")
        return CanonicalPath(raw) ?? resolvedMain
    }

    private func realPath(_ path: CanonicalPath) -> CanonicalPath? {
        guard let resolved = realpath(path.raw, nil) else { return path }
        defer { free(resolved) }
        return CanonicalPath(String(cString: resolved)) ?? path
    }

    private func resolved(_ path: CanonicalPath?) -> CanonicalPath? {
        guard let path else { return nil }
        return realPath(path) ?? path
    }

    private func canonical(_ printed: String, relativeTo worktree: CanonicalPath) -> CanonicalPath? {
        let trimmed = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let absolute = trimmed.hasPrefix("/") ? trimmed : worktree.raw + "/" + trimmed
        let standardized = URL(fileURLWithPath: absolute).standardized.path
        let stripped = standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
        guard let path = CanonicalPath(stripped) else { return nil }
        return resolved(path)
    }

    /// `core.fsmonitor` names a program `git status` would start; a read must never run one.
    private func run(_ arguments: [String]) -> GitOutput? {
        GitProcess.run(executable: Self.git, arguments: ["-c", "core.fsmonitor=false"] + arguments, timeoutSeconds: Self.timeoutSeconds)
    }
}

struct StatusSummary {
    var hasChanges = false
    var ignoredNonBuildPaths: [String] = []

    static func parse(_ output: String, buildOutputNames: Set<String>) -> StatusSummary {
        var summary = StatusSummary()
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            guard line.count >= 4 else {
                if !line.isEmpty { summary.hasChanges = true }
                continue
            }
            if line.prefix(2) == "!!" {
                let path = GitPath.unescape(String(line.dropFirst(3)))
                let trimmed = trimTrailingSlash(path)
                guard !trimmed.isEmpty else { continue }
                // Git names the ignored folder itself, however deep it sits in a monorepo; its own name decides.
                let name = trimmed.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? trimmed
                if !buildOutputNames.contains(name) { summary.ignoredNonBuildPaths.append(trimmed) }
            } else {
                summary.hasChanges = true
            }
        }
        return summary
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var text = path
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

private enum GitPath {
    static func unescape(_ field: String) -> String {
        guard field.count >= 2, field.first == "\"", field.last == "\"" else { return field }
        var output = ""
        let characters = Array(field.dropFirst().dropLast())
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character != "\\" {
                output.append(character)
                index += 1
                continue
            }
            index += 1
            guard index < characters.count else { break }
            let escaped = characters[index]
            index += 1
            switch escaped {
            case "\\": output.append("\\")
            case "\"": output.append("\"")
            case "n": output.append("\n")
            case "t": output.append("\t")
            case "r": output.append("\r")
            case "a": output.append("\u{7}")
            case "b": output.append("\u{8}")
            case "f": output.append("\u{c}")
            case "v": output.append("\u{b}")
            default:
                guard let first = octal(escaped) else {
                    output.append(escaped)
                    continue
                }
                var number = first
                var digits = 1
                while digits < 3, index < characters.count, let next = octal(characters[index]) {
                    number = number * 8 + next
                    index += 1
                    digits += 1
                }
                if let scalar = Unicode.Scalar(number) { output.append(Character(scalar)) }
            }
        }
        return output
    }

    private static func octal(_ character: Character) -> Int? {
        guard let value = character.unicodeScalars.first?.value, (48...55).contains(value) else { return nil }
        return Int(value - 48)
    }
}

private struct GitOutput {
    var status: Int32
    var output: String
}

private final class RunningGit: @unchecked Sendable {
    let process = Process()
    func stop() {
        if process.isRunning { process.terminate() }
    }
}

private enum GitProcess {
    static func run(executable: String, arguments: [String], timeoutSeconds: Int) -> GitOutput? {
        let running = RunningGit()
        let process = running.process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let stdout = Pipe()
        let collected = LockedData()
        let reader = DispatchGroup()
        reader.enter()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                reader.leave()
            } else if collected.append(chunk, limit: 8_000_000) {
                handle.readabilityHandler = nil
                running.stop()
                reader.leave()
            }
        }
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let finished = DispatchGroup()
        finished.enter()
        process.terminationHandler = { _ in finished.leave() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            running.stop()
            _ = finished.wait(timeout: .now() + .seconds(2))
            _ = reader.wait(timeout: .now() + .seconds(2))
            return nil
        }
        _ = reader.wait(timeout: .now() + .seconds(2))
        guard process.terminationReason == .exit, !collected.overflowed else { return nil }
        return GitOutput(status: process.terminationStatus, output: collected.string())
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false

    /// Returns true when the buffer passes the limit and the caller should stop the process.
    func append(_ chunk: Data, limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !overflow else { return true }
        data.append(chunk)
        if data.count > limit {
            overflow = true
            return true
        }
        return false
    }

    var overflowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return overflow
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
