/// Empty, or nothing but whitespace. Shared by the value types that refuse a blank string.
enum BlankText {
    static func isBlank(_ text: String) -> Bool { text.allSatisfy(\.isWhitespace) }
}
