import Application
import Testing

@Test func controlCharactersAreEscaped() {
    #expect(DisplayText.escaped("new\nline") == "new\\nline")
    #expect(DisplayText.escaped("a\tb\rc\u{7F}d\u{1B}") == "a\\tb\\rc\\u{7f}d\\u{1b}")
    #expect(DisplayText.escaped("ünïcødé 🚀") == "ünïcødé 🚀")
}
