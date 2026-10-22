// End-to-end check of `reclaimdisk scan --json` (plan Task 10).
// Usage: swift scripts/check-scan-json.swift <file.json> <root.takesUp> <root.freesAtLeast> <scannedUniqueBytes>
import Foundation

let args = CommandLine.arguments.dropFirst()
guard args.count == 4, let expected = Optional(args.dropFirst().compactMap { Int($0) }), expected.count == 3 else {
    FileHandle.standardError.write(Data("usage: check-scan-json.swift <file.json> <takesUp> <freesAtLeast> <scannedUniqueBytes>\n".utf8))
    exit(2)
}
let data = try Data(contentsOf: URL(fileURLWithPath: args.first!))
guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let root = json["root"] as? [String: Any] else {
    print("check-scan-json: not a schema-1 document"); exit(1)
}
let actual = [root["takesUp"] as? Int ?? -1, root["freesAtLeast"] as? Int ?? -1, json["scannedUniqueBytes"] as? Int ?? -1]
var failures: [String] = []
if json["schemaVersion"] as? Int != 1 { failures.append("schemaVersion is \(json["schemaVersion"] ?? "missing"), expected 1") }
if json["scope"] as? String != "subtree" { failures.append("scope is \(json["scope"] ?? "missing"), expected subtree") }
for (label, (got, want)) in zip(["root.takesUp", "root.freesAtLeast", "scannedUniqueBytes"], zip(actual, expected)) where got != want {
    failures.append("\(label) is \(got), expected \(want)")
}
if failures.isEmpty {
    print("check-scan-json: ok (takesUp \(actual[0]), freesAtLeast \(actual[1]), scannedUniqueBytes \(actual[2]))")
} else {
    failures.forEach { print("check-scan-json: \($0)") }
    exit(1)
}
