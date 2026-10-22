/// An absolute path in canonical form: starts with "/", no empty, "." or ".." components,
/// no trailing slash (except the root itself) and no NUL. Symlinks are not resolved here;
/// that needs the file system and happens in Infrastructure.
public struct CanonicalPath: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let raw: String

    public init?(_ raw: String) {
        guard raw.hasPrefix("/"), !raw.contains("\u{0}") else { return nil }
        if raw != "/" {
            let parts = raw.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            for part in parts where part.isEmpty || part == "." || part == ".." { return nil }
        }
        self.raw = raw
    }

    public static let root = CanonicalPath("/")!

    public var components: [String] {
        raw == "/" ? [] : raw.dropFirst().split(separator: "/").map(String.init)
    }

    public var lastComponent: String { components.last ?? "" }

    public var parent: CanonicalPath? {
        guard raw != "/" else { return nil }
        let parentComponents = components.dropLast()
        return parentComponents.isEmpty ? .root : CanonicalPath("/" + parentComponents.joined(separator: "/"))
    }

    public func appending(_ name: String) -> CanonicalPath? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\u{0}") else { return nil }
        return CanonicalPath(raw == "/" ? "/" + name : raw + "/" + name)
    }

    /// Component-wise: "/a/bc" is not a descendant of "/a/b".
    public func isSameOrDescendant(of other: CanonicalPath) -> Bool {
        let mine = components, theirs = other.components
        return mine.count >= theirs.count && Array(mine.prefix(theirs.count)) == theirs
    }

    /// For case-insensitive matching (APFS is case-insensitive by default).
    /// Unicode normalization differences are already equal under Swift's String equality.
    public var comparisonKey: String { raw.lowercased() }

    public static func < (lhs: CanonicalPath, rhs: CanonicalPath) -> Bool { lhs.raw < rhs.raw }

    public var description: String { raw }
}
