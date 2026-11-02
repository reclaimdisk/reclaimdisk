/// How to get the bytes back after a cleanup. Blank text is refused.
public struct Recovery: Hashable, Sendable {
    public let text: String

    public init?(_ text: String) {
        guard !BlankText.isBlank(text) else { return nil }
        self.text = text
    }
}
