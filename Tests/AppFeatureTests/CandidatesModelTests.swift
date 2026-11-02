@testable import AppFeature
import Application
import Catalog
import Foundation
import Inventory
import os
import SharedKernel
import Testing
import TestSupport

/// A rule whose note records which proposer built it, so a reused proposer cannot pretend to be a new one.
private struct MarkedRule: Rule, Sendable {
    let id = RuleID("marked-rule")!
    let title = "Marked rule"
    let mark: String

    func evaluate(_: RuleContext) -> RuleResult {
        RuleResult(candidates: [], notes: [RuleNote(rule: id, status: .unknown, reason: mark)])
    }
}

@MainActor
private func finishedScan() async throws -> Scan {
    let reader = FakeVolumeReader()
    let data = "/System/Volumes/Data"
    let gib = ByteCount.gibibyte.bytes
    reader.capacity(
        data,
        CapacityReading(
            total: ByteCount(100 * gib), available: ByteCount(50 * gib), availableForImportantUsage: ByteCount(50 * gib),
            usedByVolume: ByteCount(40 * gib)
        )
    )
    reader.directory(data, [Entry.file("f", allocated: ByteCount(gib), fileID: 1)])
    return try await RunScan(reader: reader, clock: FakeClock(), home: CanonicalPath("/Users/u")!)(ScanRequest(), progress: { _ in })
}

@MainActor
private func waitUntilReady(_ model: CandidatesModel) async throws {
    for _ in 0..<3_000 where { if case .ready = model.state { false } else { true } }() {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test @MainActor func twoProposalsEachBuildACatalog() async throws {
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let home = CanonicalPath("/Users/u")!
    let model = CandidatesModel(makePropose: {
        let mark = calls.withLock { state -> Int in
            state += 1
            return state
        }
        return ProposeCandidates(rules: [MarkedRule(mark: String(mark))], clock: FakeClock(), home: home)
    })
    #expect(calls.withLock { $0 } == 0)

    let scan = try await finishedScan()
    model.propose(from: scan)
    try await waitUntilReady(model)
    guard case let .ready(first) = model.state else { Issue.record("not ready: \(model.state)"); return }
    #expect(calls.withLock { $0 } == 1)
    #expect(first.notes.map(\.reason) == ["1"])

    model.propose(from: scan)
    try await waitUntilReady(model)
    guard case let .ready(second) = model.state else { Issue.record("not ready: \(model.state)"); return }
    #expect(calls.withLock { $0 } == 2)
    #expect(second.notes.map(\.reason) == ["2"])
}

/// Holds its proposal until the test lets it go, so it finishes after a newer one.
private struct GatedRule: Rule, Sendable {
    let id = RuleID("gated-rule")!
    let title = "Gated rule"
    let gate: DispatchSemaphore

    func evaluate(_: RuleContext) -> RuleResult {
        _ = gate.wait(timeout: .now() + 5)
        return RuleResult(candidates: [], notes: [RuleNote(rule: id, status: .unknown, reason: "stale")])
    }
}

@Test @MainActor func aProposalThatLostTheRaceNeverWritesItsList() async throws {
    let gate = DispatchSemaphore(value: 0)
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let home = CanonicalPath("/Users/u")!
    let model = CandidatesModel(makePropose: {
        let call = calls.withLock { state -> Int in
            state += 1
            return state
        }
        let rule: any Rule = call == 1 ? GatedRule(gate: gate) : MarkedRule(mark: "fresh")
        return ProposeCandidates(rules: [rule], clock: FakeClock(), home: home)
    })
    let scan = try await finishedScan()
    model.propose(from: scan)
    for _ in 0..<3_000 where calls.withLock({ $0 }) < 1 { try await Task.sleep(for: .milliseconds(10)) }
    model.propose(from: scan)
    try await waitUntilReady(model)
    guard case let .ready(fresh) = model.state else { Issue.record("not ready: \(model.state)"); return }
    #expect(fresh.notes.map(\.reason) == ["fresh"])

    gate.signal()
    try await Task.sleep(for: .milliseconds(300))
    guard case let .ready(after) = model.state else { Issue.record("not ready: \(model.state)"); return }
    #expect(after.notes.map(\.reason) == ["fresh"])
}
