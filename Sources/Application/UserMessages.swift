import SharedKernel

/// The only source of user-facing error text, shared by the CLI and the app.
public enum UserMessages {
    public static func text(for error: any Error) -> String {
        switch error {
        case let scanError as ScanError: text(for: scanError)
        case is CancellationError: "Scan cancelled."
        default: "Something went wrong: \(error). Please report this as a bug."
        }
    }

    /// For a `--path` that couldn't be resolved, shown with the user's own input.
    public static func text(forUnresolvablePath input: String, error: DirectoryReadError) -> String {
        unreadable(input, error)
    }

    public static func lowDiskWarning(available: ByteCount, formatted: String) -> String {
        "Only \(formatted) free. The scan needs a little space for its own memory; free some space first if it fails."
    }

    /// For folders the scan couldn't read for reasons Full Disk Access won't fix.
    public static func unreadableFolders(count: Int) -> String {
        count == 1 ? "1 folder couldn't be read, so it isn't counted." : "\(count) folders couldn't be read, so they aren't counted."
    }

    private static func text(for error: ScanError) -> String {
        switch error {
        case .notADirectory(let path): "\(path) is not a folder. Choose a folder to scan."
        case .notOnDataVolume(let path): "\(path) is not on the Mac's internal Data volume. Choose a folder on the internal disk."
        case .unreadable(let path, let readError): unreadable(path.raw, readError)
        case .inconsistentMeasurement(let detail): "The scan produced inconsistent numbers (\(detail)). Please report this as a bug."
        }
    }

    private static func unreadable(_ subject: String, _ error: DirectoryReadError) -> String {
        switch error {
        case .notPermitted:
            "\(subject) needs Full Disk Access. Grant it in System Settings › Privacy & Security › Full Disk Access, or choose another folder."
        case .permissionDenied: "\(subject) is readable only by its owner or the system. Choose another folder."
        case .notFound: "\(subject) doesn't exist. Check the path and try again."
        case .nameTooLong: couldNotRead(subject, "path too long")
        case .notADirectory: couldNotRead(subject, "not a folder")
        case .cloudOnly: "\(subject) is stored only in the cloud, so nothing in it takes up space on this Mac."
        case .other(let code): couldNotRead(subject, "errno \(code)")
        }
    }

    private static func couldNotRead(_ subject: String, _ detail: String) -> String {
        "\(subject) couldn't be read (\(detail)). Try again; if it keeps failing, please report it."
    }
}
