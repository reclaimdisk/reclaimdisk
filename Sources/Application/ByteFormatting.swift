import SharedKernel

/// One formatter for every front end (Global Constraints, "Sizes"). "Frees at least" figures use `.down`
/// so the lower bound is never overstated; everything else uses `.nearest`.
public enum ByteFormatting {
    public enum Rounding: Sendable { case nearest, down }

    private static let mebibyte: UInt64 = 1_048_576
    private static let gibibyte: UInt64 = 1_073_741_824

    /// 0 -> "0 MiB"; 1 B..<1 MiB -> "<1 MiB"; <1 GiB -> whole MiB ("300 MiB"); otherwise GiB with one decimal ("153.1 GiB").
    public static func string(_ bytes: ByteCount, rounding: Rounding) -> String {
        let value = bytes.bytes
        if value == 0 { return "0 MiB" }
        if value < mebibyte { return "<1 MiB" }
        if value < gibibyte {
            let mebibytes = rounding == .down ? value / mebibyte : (value + mebibyte / 2) / mebibyte
            if mebibytes < 1024 { return "\(mebibytes) MiB" }
        }
        let tenths = rounding == .down ? value * 10 / gibibyte : (value * 10 + gibibyte / 2) / gibibyte
        return "\(tenths / 10).\(tenths % 10) GiB"
    }

    /// 12345 -> "12,345".
    public static func grouped(_ number: Int) -> String {
        let digits = String(number)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return result
    }
}

/// Human titles for kinds, shared by the CLI and the app (the app's palette adds colors and descriptions).
public enum KindTitles {
    public static func title(for kind: Kind) -> String {
        switch kind {
        case .buildOutput: "Build output & dependencies"
        case .agentSessions: "Agent sessions & worktrees"
        case .docker: "Docker"
        case .caches: "Caches"
        case .apps: "Apps & app data"
        case .developerTools: "Developer tools & SDKs"
        case .projectSource: "Project source"
        case .personalFiles: "Personal files"
        case .macOSData: "macOS downloads & data"
        case .other: "Everything else"
        case .notReadable: "Not counted"
        }
    }
}
