import Application
import SharedKernel
import Testing

private let p = CanonicalPath("/Users/u/x")!

@Test func messagesMatchTheContract() {
    #expect(UserMessages.text(for: ScanError.notADirectory(p)) == "/Users/u/x is not a folder. Choose a folder to scan.")
    #expect(UserMessages.text(for: ScanError.notOnDataVolume(p)) == "/Users/u/x is not on the Mac's internal Data volume. Choose a folder on the internal disk.")
    #expect(UserMessages.text(for: ScanError.unreadable(p, .notPermitted)) == "/Users/u/x needs Full Disk Access. Grant it in System Settings › Privacy & Security › Full Disk Access, or choose another folder.")
    #expect(UserMessages.text(for: ScanError.unreadable(p, .permissionDenied)) == "/Users/u/x is readable only by its owner or the system. Choose another folder.")
    #expect(UserMessages.text(for: ScanError.unreadable(p, .notFound)) == "/Users/u/x doesn't exist. Check the path and try again.")
    #expect(UserMessages.text(for: ScanError.unreadable(p, .other(errno: 5))) == "/Users/u/x couldn't be read (errno 5). Try again; if it keeps failing, please report it.")
    #expect(UserMessages.text(for: ScanError.unreadable(p, .nameTooLong)) == "/Users/u/x couldn't be read (path too long). Try again; if it keeps failing, please report it.")
    #expect(UserMessages.text(for: ScanError.inconsistentMeasurement("frees > takes")) == "The scan produced inconsistent numbers (frees > takes). Please report this as a bug.")
    #expect(UserMessages.text(for: CancellationError()) == "Scan cancelled.")
    #expect(UserMessages.text(for: OddError()) == "Something went wrong: OddError(). Please report this as a bug.")
    #expect(UserMessages.lowDiskWarning(available: ByteCount(1), formatted: "<1 MiB") == "Only <1 MiB free. The scan needs a little space for its own memory; free some space first if it fails.")
}

@Test func unresolvablePathUsesTheRawInput() {
    #expect(UserMessages.text(forUnresolvablePath: "../nope", error: .notFound) == "../nope doesn't exist. Check the path and try again.")
}

@Test func cloudOnlyAndUnreadableFolderMessages() {
    #expect(UserMessages.text(for: ScanError.unreadable(p, .cloudOnly)) == "/Users/u/x is stored only in the cloud, so nothing in it takes up space on this Mac.")
    #expect(UserMessages.unreadableFolders(count: 1) == "1 folder couldn't be read, so it isn't counted.")
    #expect(UserMessages.unreadableFolders(count: 3) == "3 folders couldn't be read, so they aren't counted.")
}

private struct OddError: Error {}
