/// Names and paths as people see them, shared by the CLI and the app: control characters are shown escaped
/// (\n, \t, \r, \u{…}), so one odd name can't break a line of text output or a row in the app.
public enum DisplayText {
    public static func escaped(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: result += "\\u{\(String(scalar.value, radix: 16))}"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
