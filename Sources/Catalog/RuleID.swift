/// A stable rule name: lowercase ASCII words joined by single hyphens (`rust-build-folder`).
public struct RuleID: Hashable, Comparable, Sendable {
    public let rawValue: String

    public init?(_ rawValue: String) {
        var previousWasHyphen = false
        var sawWord = false
        for scalar in rawValue.unicodeScalars {
            if scalar == "-" {
                guard sawWord, !previousWasHyphen else { return nil }
                previousWasHyphen = true
            } else if Self.isWordCharacter(scalar) {
                sawWord = true
                previousWasHyphen = false
            } else {
                return nil
            }
        }
        guard sawWord, !previousWasHyphen else { return nil }
        self.rawValue = rawValue
    }

    public static func < (lhs: RuleID, rhs: RuleID) -> Bool { lhs.rawValue < rhs.rawValue }

    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
    }
}
