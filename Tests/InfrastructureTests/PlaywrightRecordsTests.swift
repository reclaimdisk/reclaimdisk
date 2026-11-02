import Catalog
import Foundation
import SharedKernel
import Testing
@testable import Infrastructure

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("playwright-records-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func canonical(_ url: URL) -> CanonicalPath { CanonicalPath(url.resolvingSymlinksInPath().path)! }

@Test func playwrightRecordsReadBuildsAndWhatEachLiveInstallationNeeds() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("ms-playwright")
    for name in ["chromium-1187", "chromium-1248", "chromium_headless_shell-1248", "webkit-2370", "ffmpeg-1013"] {
        try write(String(repeating: "x", count: 10_000), to: cache.appendingPathComponent("\(name)/payload.bin"))
    }
    try write("lock", to: cache.appendingPathComponent("__dirlock"))   // not a build
    let project = root.appendingPathComponent("web/node_modules/playwright-core")
    try write("""
    {"comment": "fixture", "browsers": [
      {"name": "chromium", "revision": "1248", "installByDefault": true},
      {"name": "chromium-headless-shell", "revision": "1248", "installByDefault": true},
      {"name": "webkit", "revision": "2360", "installByDefault": true, "revisionOverrides": {"mac14-arm64": "2370"}},
      {"name": "ffmpeg", "revision": "1013", "installByDefault": true}
    ]}
    """, to: project.appendingPathComponent("browsers.json"))
    try write(project.path, to: cache.appendingPathComponent(".links/aaaa"))
    try write(root.appendingPathComponent("deleted/node_modules/playwright-core").path, to: cache.appendingPathComponent(".links/bbbb"))   // dead link

    guard case let .read(snapshot) = LivePlaywrightRecords(cacheFolder: cache).read() else {
        Issue.record("expected a reading")
        return
    }
    #expect(snapshot.cacheFolder == canonical(cache))
    #expect(snapshot.builds.map { "\($0.browser)@\($0.revision)" }.sorted() == [
        "chromium-headless-shell@1248", "chromium@1187", "chromium@1248", "ffmpeg@1013", "webkit@2370",
    ])
    #expect(snapshot.builds.allSatisfy { ($0.size?.bytes ?? 0) >= 10_000 })
    let needed = Set(snapshot.requirements.map { "\($0.browser)@\($0.revision)" })
    #expect(needed.isSuperset(of: ["chromium@1248", "chromium-headless-shell@1248", "webkit@2370", "ffmpeg@1013"]))   // overrides count too
    #expect(!needed.contains("chromium@1187"))
    #expect(snapshot.requirements.allSatisfy { $0.installation == canonical(project) })   // the dead link adds nothing
}

@Test func aMissingCacheFolderMeansPlaywrightIsNotInstalled() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(LivePlaywrightRecords(cacheFolder: root.appendingPathComponent("absent")).read() == .notInstalled)
}

@Test func anUnreadableBrowsersFileMakesTheWholeReadingUnreadable() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("ms-playwright")
    try write("x", to: cache.appendingPathComponent("chromium-1187/payload.bin"))
    let project = root.appendingPathComponent("web/node_modules/playwright-core")
    try write("{ not json", to: project.appendingPathComponent("browsers.json"))
    try write(project.path, to: cache.appendingPathComponent(".links/aaaa"))
    guard case .unreadable = LivePlaywrightRecords(cacheFolder: cache).read() else {
        Issue.record("a live installation we can't read must protect every build")
        return
    }
}
