// Architecture checks for spec 7.3. Run from the repository root:
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
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            violations.append("\(name): source path \(root.path) not found")
            continue
        }
        for case let file as URL in files where file.pathExtension == "swift" {
            let contents = try String(contentsOf: file, encoding: .utf8)
            var carried = ""
            var reported = Set<String>()
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
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
            // Second pass: the compiler's own list of imports catches forms the line scan can't see
            // (an import after a block comment, the module name on the next line, …).
            for module in try compilerImports(of: file) where !allowedModules.contains(module) && !reported.contains(module) {
                violations.append("\(file.path): \(name) imports \(module), which is not in its allowed edges")
            }
        }
    }
    return violations
}

/// Attributes that call into C without any import statement; banned in domain targets.
let bannedAttributes = ["@_silgen_name", "@_extern", "@_cdecl"]

/// `swiftc -emit-imported-modules` parses the file and lists every imported module; it needs no module search paths.
func compilerImports(of file: URL) throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swiftc", "-emit-imported-modules", "-parse-as-library", file.path]
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw NSError(domain: "check-architecture", code: 2, userInfo: [NSLocalizedDescriptionKey: "swiftc couldn't list imports of \(file.path): \(message)"])
    }
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
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
    let cases: [(String, () throws -> [String], String)] = [
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
    ]
    var allPassed = true
    for (label, run, expected) in cases {
        let violations = try run()
        let hasExpected = violations.contains { $0.contains(expected) }
        let unexpected = violations.filter { !$0.contains(expected) }
        if hasExpected && unexpected.isEmpty {
            print("self-test PASS  \(label): \(expected)")
        } else {
            allPassed = false
            print("self-test FAIL  \(label): expected exactly '\(expected)', got \(violations)")
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
