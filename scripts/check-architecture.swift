// Architecture checks (see docs/architecture.md). Run from the repository root:
//   swift scripts/check-architecture.swift graph    <allowed.json> <describe.json>
//   swift scripts/check-architecture.swift imports  <allowed.json> <describe.json> <packageRoot>
//   swift scripts/check-architecture.swift settings <allowed.json> <dump.json>
//   swift scripts/check-architecture.swift self-test
// Script mode is Swift 5, so regex literals use the #/.../# form.
import Foundation

struct Allowed {
    let domainTargets: Set<String>
    let edges: [String: Set<String>]

    init(path: String) throws {
        let json = try loadJSON(path)
        domainTargets = Set(json["domainTargets"] as? [String] ?? [])
        let raw = json["edges"] as? [String: [String]] ?? [:]
        edges = raw.mapValues(Set.init)
    }
}

func loadJSON(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "check-architecture", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(path) is not a JSON object"])
    }
    return object
}

func targets(_ json: [String: Any]) -> [[String: Any]] { json["targets"] as? [[String: Any]] ?? [] }

// MARK: graph

func checkGraph(allowed: Allowed, describePath: String) throws -> [String] {
    var violations: [String] = []
    var seen = Set<String>()
    for target in targets(try loadJSON(describePath)) {
        guard let name = target["name"] as? String, (target["type"] as? String) != "test" else { continue }
        seen.insert(name)
        guard let allowedEdges = allowed.edges[name] else {
            violations.append("unknown target \(name)")
            continue
        }
        let targetDeps = target["target_dependencies"] as? [String] ?? []
        let productDeps = (target["product_dependencies"] as? [String] ?? []).map { "product:\($0)" }
        let actual = Set(targetDeps + productDeps)
        for edge in actual.subtracting(allowedEdges).sorted() { violations.append("unexpected edge \(name) -> \(edge)") }
        for edge in allowedEdges.subtracting(actual).sorted() { violations.append("missing edge \(name) -> \(edge)") }
    }
    for name in Set(allowed.edges.keys).subtracting(seen).sorted() { violations.append("missing target \(name)") }
    return violations
}

// MARK: imports

// import X | @testable import X | @preconcurrency internal import X | public import struct X.Y | package import X
let importStatement = #/^\s*((?:@[A-Za-z_]+(?:\([^)]*\))?\s+)*)(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)/#
let attributeOnly = #/^\s*(?:@[A-Za-z_]+(?:\([^)]*\))?\s*)+$/#

func checkImports(allowed: Allowed, describePath: String, packageRoot: String) throws -> [String] {
    var violations: [String] = []
    for target in targets(try loadJSON(describePath)) {
        guard let name = target["name"] as? String, allowed.domainTargets.contains(name),
              let relativePath = target["path"] as? String else { continue }
        let allowedModules = allowed.edges[name] ?? []
        let root = URL(fileURLWithPath: packageRoot).appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            violations.append("\(name): source path \(root.path) not found")
            continue
        }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        var reported = Set<String>()
        for file in files {
            guard let code = codeOnly(try String(contentsOf: file, encoding: .utf8)) else {
                violations.append("\(file.path): a comment or string never ends, so \(name)'s imports can't be checked")
                continue
            }
            var carried = ""
            for (index, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for piece in line.split(separator: ";", omittingEmptySubsequences: true) {
                    let statement = String(piece)
                    if statement.wholeMatch(of: attributeOnly) != nil {
                        carried += statement + " "
                        continue
                    }
                    let candidate = carried + statement
                    carried = ""
                    guard let match = candidate.firstMatch(of: importStatement) else { continue }
                    let location = "\(file.path):\(index + 1)"
                    let attributes = String(match.1), module = String(match.2)
                    if attributes.contains("@_exported") {
                        violations.append("\(location): @_exported import is not allowed in domain target \(name)")
                    }
                    if !allowedModules.contains(module) {
                        violations.append("\(location): \(name) imports \(module), which is not in its allowed edges")
                        reported.insert(module)
                    }
                }
                for attribute in bannedAttributes where line.contains(attribute) {
                    violations.append("\(file.path):\(index + 1): \(name) uses \(attribute), which reaches C symbols without an import")
                }
            }
        }
        // Second pass: the compiler's own list of imports catches forms the line scan can't see
        // (the module name on the next line, an import inside #if, …). One call covers the whole target;
        // files are named only when it finds something.
        let found = try compilerImports(of: files).subtracting(allowedModules).subtracting(reported)
        if !found.isEmpty {
            for file in files {
                for module in try compilerImports(of: [file]).intersection(found).sorted() {
                    violations.append("\(file.path): \(name) imports \(module), which is not in its allowed edges")
                }
            }
        }
    }
    return violations
}

/// Attributes that call into C without any import statement; banned in domain targets.
let bannedAttributes = ["@_silgen_name", "@_extern", "@_cdecl"]

/// The compilation conditions `swift build -v` passes to domain targets, in debug and in release (Swift 6.2).
/// Domain targets declare no settings of their own (see `settings`), so every `#if` in them sees one of these sets.
let buildConditions = [
    ["SWIFT_PACKAGE", "DEBUG", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE"],
    ["SWIFT_PACKAGE", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE"],
]

/// `swiftc -emit-imported-modules` parses the files and lists every imported module; it needs no module search paths.
/// It runs once per build configuration, because an import inside `#if DEBUG` exists only in debug builds.
func compilerImports(of files: [URL]) throws -> Set<String> {
    guard !files.isEmpty else { return [] }
    var modules = Set<String>()
    for conditions in buildConditions {
        let arguments = ["swiftc", "-emit-imported-modules", "-parse-as-library"] + conditions.flatMap { ["-D", $0] } + files.map(\.path)
        let result = try run("/usr/bin/xcrun", arguments)
        guard result.status == 0 else {
            let message = String(decoding: result.errors.prefix(4_000), as: UTF8.self)
            let names = files.map(\.path).joined(separator: ", ")
            throw NSError(domain: "check-architecture", code: 2, userInfo: [NSLocalizedDescriptionKey: "swiftc couldn't list imports of \(names): \(message)"])
        }
        modules.formUnion(String(decoding: result.output, as: UTF8.self).split(separator: "\n").map(String.init))
    }
    return modules
}

/// Runs a tool to completion. Both pipes are read at once: reading one to the end first stalls a tool that
/// fills the other pipe's buffer, and the check would never finish.
func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: Data, errors: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    var errorData = Data()
    let errorsRead = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        errorData = errors.fileHandleForReading.readDataToEndOfFile()
        errorsRead.signal()
    }
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    errorsRead.wait()
    process.waitUntilExit()
    return (process.terminationStatus, outputData, errorData)
}

/// `source` with comments and the text of string literals blanked out, so the line scan sees only code. Newlines stay,
/// so line numbers still match. Follows Swift's lexical rules: block comments nest; strings may be multiline or
/// `#`-delimited; an interpolation's code is kept; a `#/…/#` regex is skipped. Nil when a comment or string never ends.
func codeOnly(_ source: String) -> String? {
    var lexer = CodeLexer(bytes: Array(source.utf8))
    guard lexer.code(inInterpolation: false) else { return nil }
    return String(decoding: lexer.bytes, as: UTF8.self)
}

struct CodeLexer {
    var bytes: [UInt8]
    var i = 0

    static let newline = UInt8(ascii: "\n"), space = UInt8(ascii: " "), quote = UInt8(ascii: "\""), hash = UInt8(ascii: "#")
    static let slash = UInt8(ascii: "/"), backslash = UInt8(ascii: "\\"), open = UInt8(ascii: "("), close = UInt8(ascii: ")")

    func at(_ k: Int, _ text: String) -> Bool {
        let pattern = text.utf8
        return k + pattern.count <= bytes.count && bytes[k..<(k + pattern.count)].elementsEqual(pattern)
    }

    func hashes(from k: Int) -> Int {
        var n = 0
        while k + n < bytes.count && bytes[k + n] == Self.hash { n += 1 }
        return n
    }

    mutating func blank(_ range: Range<Int>) {
        for k in range where bytes[k] != Self.newline { bytes[k] = Self.space }
    }

    /// Code up to the end, or up to the `)` that closes an interpolation. False when something never ends.
    mutating func code(inInterpolation: Bool) -> Bool {
        var depth = 0
        while i < bytes.count {
            if at(i, "//") {
                let start = i
                while i < bytes.count && bytes[i] != Self.newline { i += 1 }
                blank(start..<i)
            } else if at(i, "/*") {
                let start = i
                var nesting = 0
                repeat {
                    if at(i, "/*") { nesting += 1; i += 2 } else if at(i, "*/") { nesting -= 1; i += 2 } else { i += 1 }
                } while nesting > 0 && i < bytes.count
                guard nesting == 0 else { return false }
                blank(start..<i)
            } else if bytes[i] == Self.quote || bytes[i] == Self.hash {
                let delimiter = hashes(from: i), next = i + delimiter
                if next < bytes.count && bytes[next] == Self.quote {
                    i = next
                    guard string(delimiter: delimiter) else { return false }
                } else if delimiter > 0 && next < bytes.count && bytes[next] == Self.slash {
                    let start = next + 1   // a #/…/# regex may hold quotes: skip to its end
                    i = start
                    while i < bytes.count && !(bytes[i] == Self.slash && hashes(from: i + 1) >= delimiter) { i += 1 }
                    guard i < bytes.count else { return false }
                    blank(start..<i)
                    i += 1 + delimiter
                } else {
                    i = next   // #if, #selector, …
                }
            } else {
                if inInterpolation && bytes[i] == Self.open { depth += 1 }
                if inInterpolation && bytes[i] == Self.close {
                    if depth == 0 { i += 1; return true }
                    depth -= 1
                }
                i += 1
            }
        }
        return !inInterpolation
    }

    /// The string literal whose opening quote is at `i`, with `delimiter` number signs before it.
    mutating func string(delimiter: Int) -> Bool {
        let quotes = at(i, "\"\"\"") ? 3 : 1
        i += quotes
        var start = i
        while i < bytes.count {
            if bytes[i] == Self.backslash && hashes(from: i + 1) >= delimiter {
                let after = i + 1 + delimiter
                if after < bytes.count && bytes[after] == Self.open {
                    blank(start..<(after + 1))
                    i = after + 1
                    guard code(inInterpolation: true) else { return false }
                    start = i
                } else {
                    i = after + 1   // an escape: skip the escaped character
                }
            } else if (quotes == 3 ? at(i, "\"\"\"") : bytes[i] == Self.quote) && hashes(from: i + quotes) >= delimiter {
                blank(start..<i)
                i += quotes + delimiter
                return true
            } else if quotes == 1 && bytes[i] == Self.newline {
                return false
            } else {
                i += 1
            }
        }
        return false
    }
}

// MARK: settings

func checkSettings(allowed: Allowed, dumpPath: String) throws -> [String] {
    targets(try loadJSON(dumpPath)).compactMap { target in
        guard let name = target["name"] as? String, allowed.domainTargets.contains(name) else { return nil }
        let settings = target["settings"] as? [Any] ?? []
        return settings.isEmpty ? nil : "\(name) declares build settings; domain targets may not"
    }
}

// MARK: self-test

func selfTest() throws -> Bool {
    let allowed = try Allowed(path: "architecture/allowed-dependencies.json")
    let fixtures = "ArchitectureFixtures"
    // nil expects no violations at all.
    let cases: [(String, () throws -> [String], String?)] = [
        ("graph: extra edge", { try checkGraph(allowed: allowed, describePath: "\(fixtures)/describe-extra-edge.json") },
         "unexpected edge Cleanup -> Inventory"),
        ("imports: ';'-joined Foundation", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-foundation/describe.json", packageRoot: "\(fixtures)/imports-foundation")
        }, "Inventory imports Foundation"),
        ("imports: internal import Foundation", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-access-level/describe.json", packageRoot: "\(fixtures)/imports-access-level")
        }, "Inventory imports Foundation"),
        ("imports: @_exported on its own line", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-exported/describe.json", packageRoot: "\(fixtures)/imports-exported")
        }, "@_exported import is not allowed"),
        ("settings: unsafe flags", { try checkSettings(allowed: allowed, dumpPath: "\(fixtures)/dump-unsafe-flags.json") },
         "Inventory declares build settings"),
        ("imports: block comment before import", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-block-comment/describe.json", packageRoot: "\(fixtures)/imports-block-comment")
        }, "Inventory imports Foundation"),
        ("imports: module name on the next line", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-split-line/describe.json", packageRoot: "\(fixtures)/imports-split-line")
        }, "Inventory imports Darwin"),
        ("imports: @_silgen_name", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-silgen/describe.json", packageRoot: "\(fixtures)/imports-silgen")
        }, "Inventory uses @_silgen_name"),
        ("imports: inside #if DEBUG", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-if-debug/describe.json", packageRoot: "\(fixtures)/imports-if-debug")
        }, "Inventory imports Foundation"),
        ("imports: inside #if !DEBUG", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-if-release/describe.json", packageRoot: "\(fixtures)/imports-if-release")
        }, "Inventory imports Darwin"),
        ("imports: attributes named in comments and strings", {
            try checkImports(allowed: allowed, describePath: "\(fixtures)/attributes-in-comments/describe.json", packageRoot: "\(fixtures)/attributes-in-comments")
        }, nil),
        ("imports: swiftc writes a long error log", {
            // Over a pipe buffer of errors (about 64 KiB): the check must report it, not wait forever.
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("check-architecture-noisy-\(getpid())")
            let sources = root.appendingPathComponent("Sources/Inventory")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try String(repeating: "let = \n", count: 2_000).write(to: sources.appendingPathComponent("Bad.swift"), atomically: true, encoding: .utf8)
            do {
                return try checkImports(allowed: allowed, describePath: "\(fixtures)/imports-split-line/describe.json", packageRoot: root.path)
            } catch {
                return [error.localizedDescription]
            }
        }, "swiftc couldn't list imports"),
    ]
    var allPassed = true
    for (label, run, expected) in cases {
        let violations = try run()
        let passed: Bool
        if let expected {
            passed = violations.contains { $0.contains(expected) } && violations.allSatisfy { $0.contains(expected) }
        } else {
            passed = violations.isEmpty
        }
        if passed {
            print("self-test PASS  \(label): \(expected ?? "no violations")")
        } else {
            allPassed = false
            print("self-test FAIL  \(label): expected \(expected.map { "exactly '\($0)'" } ?? "no violations"), got \(violations)")
        }
    }
    return allPassed
}

// MARK: main

func report(_ violations: [String], mode: String) -> Int32 {
    if violations.isEmpty {
        print("\(mode): ok")
        return 0
    }
    violations.forEach { print($0) }
    return 1
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "graph" where args.count == 3:
        exit(report(try checkGraph(allowed: Allowed(path: args[1]), describePath: args[2]), mode: "graph"))
    case "imports" where args.count == 4:
        exit(report(try checkImports(allowed: Allowed(path: args[1]), describePath: args[2], packageRoot: args[3]), mode: "imports"))
    case "settings" where args.count == 3:
        exit(report(try checkSettings(allowed: Allowed(path: args[1]), dumpPath: args[2]), mode: "settings"))
    case "self-test" where args.count == 1:
        exit(try selfTest() ? 0 : 1)
    default:
        FileHandle.standardError.write(Data("usage: check-architecture.swift graph|imports|settings|self-test …\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("check-architecture: \(error.localizedDescription)\n".utf8))
    exit(1)
}
