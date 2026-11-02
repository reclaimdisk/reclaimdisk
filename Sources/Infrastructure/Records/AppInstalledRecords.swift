import AppKit
import Catalog
import Foundation
import SharedKernel

/// Apps in the usual application folders, and the bundle ids running now.
struct LiveAppRecords: AppRecords {
    var home: CanonicalPath

    init(home: CanonicalPath) { self.home = home }

    func read() -> AppReading {
        var installed: [InstalledApp] = []
        var seen = Set<String>()
        for root in roots {
            switch apps(at: root) {
            case .failure(let reason): return .unreadable(reason)
            case .found(let found):
                for app in found {
                    let key = app.bundleID.lowercased()
                    guard seen.insert(key).inserted else { continue }
                    installed.append(app)
                }
            }
        }
        return .read(AppSnapshot(installed: installed, runningBundleIDs: runningBundleIDs()))
    }

    private var roots: [URL] {
        var urls = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        ]
        if let applications = home.appending("Applications") {
            urls.append(URL(fileURLWithPath: applications.raw, isDirectory: true))
        }
        urls.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        return urls
    }

    /// Top level and one folder down. A missing folder is an empty list; one that exists but can't be listed is not.
    private func apps(at root: URL) -> AppList {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return .found([]) }
        guard isDirectory.boolValue else { return .found([]) }
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch { return .failure("Can't list \(root.path).") }
        var found: [InstalledApp] = []
        for child in children {
            if isApp(child) {
                if let app = installedApp(at: child) { found.append(app) }
                continue
            }
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let nested: [URL]
            do { nested = try FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) }
            catch { return .failure("Can't list \(child.path).") }
            for item in nested where isApp(item) {
                if let app = installedApp(at: item) { found.append(app) }
            }
        }
        return .found(found)
    }

    private func isApp(_ url: URL) -> Bool { url.pathExtension.lowercased() == "app" }

    private func installedApp(at bundle: URL) -> InstalledApp? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = object as? [String: Any],
              let bundleID = nonBlank(info["CFBundleIdentifier"]) else { return nil }
        let name = nonBlank(info["CFBundleDisplayName"])
            ?? nonBlank(info["CFBundleName"])
            ?? nonBlank(bundle.deletingPathExtension().lastPathComponent)
        guard let name else { return nil }
        return InstalledApp(bundleID: bundleID, name: name)
    }

    /// `NSWorkspace` is main-actor isolated. The candidate pass runs off the main thread.
    private func runningBundleIDs() -> Set<String> {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { Self.currentBundleIDs() }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { Self.currentBundleIDs() } }
    }

    @MainActor
    private static func currentBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

private enum AppList {
    case failure(String)
    case found([InstalledApp])
}

private func nonBlank(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
