/// Every kept folder of a finished scan. Rules read through this and never through the scanner.
public protocol ScanQuery: Sendable {
    func folders() -> [ScannedFolder]
}
