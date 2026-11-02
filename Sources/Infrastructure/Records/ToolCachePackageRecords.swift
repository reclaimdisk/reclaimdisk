import Catalog
import Foundation
import SharedKernel

/// Asks each package manager where its cache is. The clean command is recorded and never run.
struct LivePackageCacheRecords: PackageCacheRecords {
    private let home: CanonicalPath

    init(home: CanonicalPath) { self.home = home }

    func read() -> [PackageCacheReading] {
        let directories = binaryDirectories(home: home)
        let environment = PackageCacheLayout.queryEnvironment(home: home, path: directories.joined(separator: ":"))
        return CacheQuery.all.map { query in reading(query, directories: directories, environment: environment) }
    }

    private func reading(_ query: CacheQuery, directories: [String], environment: [String: String]) -> PackageCacheReading {
        guard let executable = ToolCacheCommand.executable(named: query.executable, in: directories) else {
            return .notInstalled(tool: query.tool)
        }
        guard let output = ToolCacheCommand.run(executable: executable, arguments: query.arguments, environment: environment) else {
            return .unparseable(tool: query.tool, reason: "couldn't start \(query.display)")
        }
        if output.timedOut { return .unparseable(tool: query.tool, reason: "timed out after 10 s") }
        if output.status != 0 { return .unparseable(tool: query.tool, reason: failureReason(output, command: query.display)) }
        guard let pathText = pathText(in: output.standardOutput) else {
            let blank = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let reason = blank ? "\(query.display) printed nothing" : "\(query.display) did not print a path"
            return .unparseable(tool: query.tool, reason: reason)
        }
        guard let reported = resolve(pathText, home: home),
              let folder = PackageCacheLayout.cleanedFolder(tool: query.tool, reported: reported) else {
            return .unparseable(tool: query.tool, reason: "\(query.display) path could not be resolved")
        }
        guard let clean = ToolCommand(executable: query.executable, arguments: query.cleanArguments) else {
            return .unparseable(tool: query.tool, reason: "\(query.tool) has no clean command")
        }
        let busy = query.watchesLock ? uvBusyReason(environment: environment) : nil
        return .found(PackageCache(tool: query.tool, folder: folder, clean: clean, clearsWholeFolder: query.clearsWholeFolder, busyReason: busy))
    }
}

/// Where each package manager's clean command works, and the environment its queries run in.
enum PackageCacheLayout {
    /// `npm cache clean --force` empties `<cache>/_cacache` and leaves `_npx` and `_logs`; the others clean the folder they
    /// report.
    static func cleanedFolder(tool: String, reported: CanonicalPath) -> CanonicalPath? {
        tool == "npm" ? reported.appending("_cacache") : reported
    }

    /// HOME and PATH, with every update check off: a query must not write a file or reach the network.
    static func queryEnvironment(home: CanonicalPath, path: String) -> [String: String] {
        [
            "HOME": home.raw, "PATH": path, "npm_config_update_notifier": "false", "PIP_DISABLE_PIP_VERSION_CHECK": "1",
            "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
        ]
    }
}

private struct CacheQuery {
    var tool: String
    var executable: String
    var arguments: [String]
    var cleanArguments: [String]
    var clearsWholeFolder: Bool
    var watchesLock: Bool

    var display: String { ([executable] + arguments).joined(separator: " ") }

    static let all: [CacheQuery] = [
        CacheQuery(tool: "npm", executable: "npm", arguments: ["config", "get", "cache"], cleanArguments: ["cache", "clean", "--force"],
                   clearsWholeFolder: true, watchesLock: false),
        CacheQuery(tool: "pnpm", executable: "pnpm", arguments: ["store", "path"], cleanArguments: ["store", "prune"],
                   clearsWholeFolder: false, watchesLock: false),
        CacheQuery(tool: "pip", executable: "pip3", arguments: ["cache", "dir"], cleanArguments: ["cache", "purge"],
                   clearsWholeFolder: true, watchesLock: false),
        CacheQuery(tool: "brew", executable: "brew", arguments: ["--cache"], cleanArguments: ["cleanup", "--prune=all"],
                   clearsWholeFolder: false, watchesLock: false),
        CacheQuery(tool: "uv", executable: "uv", arguments: ["cache", "dir"], cleanArguments: ["cache", "prune"],
                   clearsWholeFolder: false, watchesLock: true),
    ]
}

private func binaryDirectories(home: CanonicalPath) -> [String] {
    var directories = ["/opt/homebrew/bin", "/usr/local/bin"]
    if let bin = home.appending(".local")?.appending("bin") { directories.append(bin.raw) }
    if let bin = home.appending(".cargo")?.appending("bin") { directories.append(bin.raw) }
    return directories
}

/// The last absolute path wins, so a warning printed above the path is ignored.
private func pathText(in output: String) -> String? {
    output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.last { line in
        line.hasPrefix("/") || line.hasPrefix("~/") || line == "~"
    }
}

private func resolve(_ text: String, home: CanonicalPath) -> CanonicalPath? {
    let expanded: String
    if text == "~" {
        expanded = home.raw
    } else if text.hasPrefix("~/") {
        expanded = home.raw + String(text.dropFirst())
    } else {
        expanded = text
    }
    if let resolved = try? PathResolver.resolve(expanded, currentDirectory: home) { return resolved }
    return CanonicalPath(expanded)
}

private func uvBusyReason(environment: [String: String]) -> String? {
    guard let output = ToolCacheCommand.run(executable: "/bin/ps", arguments: ["-ax", "-o", "comm="], environment: environment),
          !output.timedOut, output.status == 0 else { return nil }
    let count = output.standardOutput.split(whereSeparator: \.isNewline).reduce(into: 0) { count, line in
        let name = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init) ?? ""
        if name == "uv" || name == "uvx" { count += 1 }
    }
    guard count > 0 else { return nil }
    return "uv is running (\(count) processes) and holds its cache lock"
}

private func failureReason(_ output: ToolCacheCommand.Output, command: String) -> String {
    let error = output.standardError.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !error.isEmpty { return String(error.prefix(300)) }
    let stdout = output.standardOutput.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !stdout.isEmpty { return String(stdout.prefix(300)) }
    return "\(command) exited with status \(output.status)"
}
