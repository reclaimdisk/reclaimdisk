import Application
import SharedKernel
import Testing

@Test(arguments: [
    (UInt64(0), "0 MiB", "0 MiB"),
    (1, "<1 MiB", "<1 MiB"),
    (314_572_800, "300 MiB", "300 MiB"),
    (1_073_741_824, "1.0 GiB", "1.0 GiB"),
    (1_288_490_188, "1.2 GiB", "1.1 GiB"),
    (1_610_612_736, "1.5 GiB", "1.5 GiB"),
])
func byteFormattingTable(bytes: UInt64, nearest: String, down: String) {
    #expect(ByteFormatting.string(ByteCount(bytes), rounding: .nearest) == nearest)
    #expect(ByteFormatting.string(ByteCount(bytes), rounding: .down) == down)
}

@Test func nearestRoundingUpToAGibibyteSwitchesUnits() {
    #expect(ByteFormatting.string(ByteCount(1_073_741_000), rounding: .nearest) == "1.0 GiB")
    #expect(ByteFormatting.string(ByteCount(1_073_741_000), rounding: .down) == "1023 MiB")
}

@Test func kindTitlesAreHumanReadable() {
    #expect(KindTitles.title(for: .buildOutput) == "Build output & dependencies")
    #expect(KindTitles.title(for: .notReadable) == "Not counted")
}
