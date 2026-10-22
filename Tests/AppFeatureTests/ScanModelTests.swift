import AppFeature
import Application
import Foundation
import SharedKernel
import Testing
import TestSupport

private let data = "/System/Volumes/Data"

private func volume(available: ByteCount = mib(200_000)) -> FakeVolumeReader {
    let reader = FakeVolumeReader()
    reader.capacity(data, CapacityReading(total: mib(500_000), available: available, availableForImportantUsage: available, usedByVolume: mib(100)))
    reader.directory(data, [Entry.dir("Users")])
    reader.directory("\(data)/Users", [Entry.file("f", allocated: mib(50), fileID: 1)])
    return reader
}

@MainActor
private func waitFor(_ model: ScanModel, timeout: Duration = .seconds(3), _ condition: (ScanModel.State) -> Bool) async -> Bool {
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition(model.state) { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition(model.state)
}

@MainActor
private func model(_ reader: FakeVolumeReader) -> ScanModel {
    ScanModel(runScan: RunScan(reader: reader, clock: FakeClock(), home: CanonicalPath("/Users/u")!))
}

@Test @MainActor func scanMovesFromScanningToFinished() async {
    let m = model(volume())
    m.start()
    if case .scanning = m.state {} else { Issue.record("expected .scanning right after start, got \(m.state)") }
    #expect(await waitFor(m) { if case .finished = $0 { true } else { false } })
}

@Test @MainActor func readerErrorShowsTheUserMessage() async {
    let reader = volume()
    reader.failingCapacity(data, .permissionDenied)
    let m = model(reader)
    m.start()
    let expected = UserMessages.text(for: ScanError.unreadable(CanonicalPath(data)!, .permissionDenied))
    #expect(await waitFor(m) { $0 == .failed(message: expected) })
}

@Test @MainActor func cancelReturnsToIdleAndNeverFinishes() async {
    let reader = volume()
    reader.directory("\(data)/Users", (0..<200).map { Entry.dir("d\($0)") })
    for i in 0..<200 { reader.directory("\(data)/Users/d\(i)", []) }
    reader.onRead = { _, _ in usleep(20_000) }
    let m = model(reader)
    m.start()
    #expect(await waitFor(m) { if case .scanning = $0 { true } else { false } })
    let started = ContinuousClock.now
    m.cancel()
    #expect(await waitFor(m, timeout: .seconds(1)) { if case .idle = $0 { true } else { false } })
    #expect(ContinuousClock.now - started < .seconds(1))
    try? await Task.sleep(for: .milliseconds(300))
    if case .finished = m.state { Issue.record("a cancelled scan must never reach .finished") }
}

@Test @MainActor func lowDiskShowsAWarningWhileIdle() {
    let m = model(volume(available: mib(100)))
    #expect(m.state == .idle(lowDiskWarning: UserMessages.lowDiskWarning(available: mib(100), formatted: "100 MiB")))
    #expect(model(volume()).state == .idle(lowDiskWarning: nil))
}
