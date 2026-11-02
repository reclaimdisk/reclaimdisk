import SharedKernel

/// A read of Playwright's downloaded browsers. Reading does not install or delete anything.
public protocol PlaywrightRecords: Sendable {
    func read() -> PlaywrightReading
}

public enum PlaywrightReading: Sendable, Equatable {
    /// No browser cache folder on this Mac.
    case notInstalled
    /// A live installation's needs could not be read, so no build is safe to remove.
    case unreadable(String)
    case read(PlaywrightSnapshot)
}

/// Browsers in the cache, and every revision a live installation's `browsers.json` names.
public struct PlaywrightSnapshot: Sendable, Equatable {
    public let cacheFolder: CanonicalPath
    public let builds: [PlaywrightBuild]
    public let requirements: [PlaywrightRequirement]

    public init(cacheFolder: CanonicalPath, builds: [PlaywrightBuild], requirements: [PlaywrightRequirement]) {
        self.cacheFolder = cacheFolder
        self.builds = builds
        self.requirements = requirements
    }
}

/// One downloaded browser build. `browser` uses hyphens, as `browsers.json` does.
public struct PlaywrightBuild: Sendable, Equatable {
    public let browser: String
    public let revision: String
    public let folder: CanonicalPath
    public let size: ByteCount?

    public init(browser: String, revision: String, folder: CanonicalPath, size: ByteCount?) {
        self.browser = browser
        self.revision = revision
        self.folder = folder
        self.size = size
    }
}

/// One revision an installation still needs. Override revisions are included, whichever platform they name.
public struct PlaywrightRequirement: Sendable, Equatable {
    public let installation: CanonicalPath
    public let browser: String
    public let revision: String

    public init(installation: CanonicalPath, browser: String, revision: String) {
        self.installation = installation
        self.browser = browser
        self.revision = revision
    }
}

/// Installed apps and the ones running now. Reading does not launch or quit anything.
public protocol AppRecords: Sendable {
    func read() -> AppReading
}

public enum AppReading: Sendable, Equatable {
    case unreadable(String)
    case read(AppSnapshot)
}

public struct AppSnapshot: Sendable, Equatable {
    public let installed: [InstalledApp]
    public let runningBundleIDs: Set<String>

    public init(installed: [InstalledApp], runningBundleIDs: Set<String>) {
        self.installed = installed
        self.runningBundleIDs = runningBundleIDs
    }
}

public struct InstalledApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}
