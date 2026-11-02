@testable import AppFeature
import AppKit
import Application
import Catalog
import Foundation
import SharedKernel
import SwiftUI
import Testing
import TestSupport

private let now = Instant(nanosecondsSince1970: 1_800_000_000_000_000_000)
private let gib = ByteCount.gibibyte.bytes

private func measured(_ rule: String, _ raw: String, kind: Kind, frees: UInt64, blocked: String? = nil) -> Candidate {
    let path = CanonicalPath(raw)!
    return try! Candidate(
        rule: RuleID(rule)!, title: rule == "rust-build-folder" ? "Rust build folder" : "Node dependencies", kind: kind,
        target: .path(path), reclaimClass: .rebuildable,
        estimate: try! .measured(freesAtLeast: ByteCount(frees), takesUp: ByteCount(frees + gib)),
        evidence: [Evidence(fact: "Holds CACHEDIR.TAG and .rustc_info.json", source: .scan, observedAt: now)!],
        recovery: Recovery("cargo build"), action: .deletePath(path), newestChange: nil, isInstalledRuntime: false,
        blockedReason: blocked, explanation: nil
    )
}

private let docker = try! Candidate(
    rule: RuleID("docker-build-cache")!, title: "Docker build cache", kind: .docker,
    target: .toolResource(tool: "docker", identifier: "build-cache"), reclaimClass: .toolManaged,
    estimate: try! .toolReported(tool: "docker", size: ByteCount(6 * gib)),
    evidence: [Evidence(fact: "Docker reports reclaimable build cache", source: .toolRecords("docker"), observedAt: now)!],
    recovery: Recovery("Rebuilt on the next build"),
    action: .toolCommand(ToolCommand(executable: "docker", arguments: ["builder", "prune", "-f"])!), newestChange: nil,
    isInstalledRuntime: false, blockedReason: nil, explanation: nil
)

private let leftover = try! Candidate(
    rule: RuleID("simulator-download-leftovers")!, title: "Simulator download no runtime uses", kind: .developerTools,
    target: .path(CanonicalPath("/System/Library/AssetsV2/x/cc1f.asset")!), reclaimClass: .reportOnly, estimate: .unknown,
    evidence: [Evidence(fact: "No simulator runtime uses this 18.0 download", source: .toolRecords("simctl"), observedAt: now)!],
    recovery: nil, action: nil, newestChange: nil, isInstalledRuntime: false, blockedReason: nil,
    explanation: "There's no documented way to remove it."
)

private func list() -> CandidateList {
    CandidateList(
        candidates: [
            measured("rust-build-folder", "/Users/u/Projects/app/target", kind: .buildOutput, frees: 12 * gib),
            measured("rust-build-folder", "/Users/u/Projects/live/target", kind: .buildOutput, frees: 30 * gib,
                     blocked: "Changed in the last 24 hours. Wait until no build uses it."),
            measured("node-dependencies", "/Users/u/Projects/web/node_modules", kind: .buildOutput, frees: 2 * gib),
            docker, leftover,
        ],
        notes: [RuleNote(rule: RuleID("android-images")!, status: .notApplicable, reason: "The Android SDK isn't installed")],
        generatedAt: now
    )
}

@Test func groupsFollowKindOrderAndTotalOnlyWhatIsSelectedByDefault() {
    let groups = CandidateGroups.make(list())
    #expect(groups.map(\.kind) == [.buildOutput, .docker, .developerTools])
    #expect(groups.first?.title == KindTitles.title(for: .buildOutput))
    #expect(groups.first?.candidates.count == 3)                                   // blocked rows stay visible
    #expect(groups.first?.selectedByDefaultFreesAtLeast == ByteCount(14 * gib))    // 12 + 2; the blocked 30 GiB doesn't count
    #expect(CandidateGroups.selectedByDefaultFreesAtLeast(list()) == ByteCount(14 * gib))
    #expect(CandidateGroups.selectedByDefaultCount(list()) == 2)
}

@Test func rowTextLeadsWithFreesAtLeastAndNamesWhoReportedASize() {
    let rust = CandidateRowText(list().candidates[0])
    #expect(rust.estimate == "Frees at least 12.0 GiB")
    #expect(rust.badge == "Rebuildable")
    #expect(rust.detail == "Comes back with: cargo build")
    #expect(rust.blocked == nil)
    #expect(rust.isSelectedByDefault)

    let blocked = CandidateRowText(list().candidates[1])
    #expect(blocked.blocked == "Changed in the last 24 hours. Wait until no build uses it.")
    #expect(blocked.isSelectedByDefault == false)

    let tool = CandidateRowText(docker)
    #expect(tool.estimate == "Docker reports 6.0 GiB")
    #expect(tool.badge == "Tool-managed")

    let report = CandidateRowText(leftover)
    #expect(report.estimate == "Size unknown")
    #expect(report.badge == "Report only")
    #expect(report.detail == "There's no documented way to remove it.")
    #expect(report.isSelectedByDefault == false)
    #expect(report.target == "/System/Library/AssetsV2/x/cc1f.asset")
    #expect(tool.target == "Docker: build-cache")
}

private struct FixedRule: Rule {
    let id = RuleID("fixed-rule")!
    let title = "Fixed rule"
    func evaluate(_ context: RuleContext) -> RuleResult {
        RuleResult(candidates: [measured("rust-build-folder", "/Users/u/Projects/app/target", kind: .buildOutput, frees: gib)], notes: [])
    }
}

@Test @MainActor func theModelProposesCandidatesForAFinishedScan() async throws {
    let reader = FakeVolumeReader()
    let data = "/System/Volumes/Data"
    reader.capacity(data, CapacityReading(total: ByteCount(100 * gib), available: ByteCount(50 * gib), availableForImportantUsage: ByteCount(50 * gib), usedByVolume: ByteCount(40 * gib)))
    reader.directory(data, [Entry.file("f", allocated: ByteCount(gib), fileID: 1)])
    let scan = try await RunScan(reader: reader, clock: FakeClock(), home: CanonicalPath("/Users/u")!)(ScanRequest(), progress: { _ in })
    let model = CandidatesModel(propose: ProposeCandidates(rules: [FixedRule()], clock: FakeClock(start: now), home: CanonicalPath("/Users/u")!))
    #expect(model.state == .idle)
    model.propose(from: scan)
    for _ in 0..<3_000 where { if case .ready = model.state { false } else { true } }() { try await Task.sleep(for: .milliseconds(10)) }
    guard case let .ready(proposed) = model.state else { Issue.record("not ready: \(model.state)"); return }
    #expect(proposed.candidates.map(\.id.rawValue) == ["rust-build-folder:/Users/u/Projects/app/target"])
}

@Test @MainActor func cleanupRendersInBothAppearances() throws {
    for scheme in [ColorScheme.light, .dark] {
        let view = CleanupContent(list: list())
            .frame(width: 900, height: 640)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "no image for \(scheme)")
        #expect(image.width == 1800 && image.height == 1280)
        #expect(colors(in: image) >= 12, "the \(scheme) rendering is blank or nearly blank")
        if let directory = ProcessInfo.processInfo.environment["RECLAIMDISK_SNAPSHOT_DIR"] {
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("cleanup-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}

private func colors(in image: CGImage) -> Int {
    let rep = NSBitmapImageRep(cgImage: image)
    var seen = Set<String>()
    for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
            if let color = rep.colorAt(x: x, y: y) {
                seen.insert("\(Int(color.redComponent * 255))-\(Int(color.greenComponent * 255))-\(Int(color.blueComponent * 255))")
            }
        }
    }
    return seen.count
}
