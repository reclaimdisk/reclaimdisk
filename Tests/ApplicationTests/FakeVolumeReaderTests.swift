import Application
import SharedKernel
import Testing
import TestSupport

@Test func fakeReaderServesLogsAndReverses() throws {
    let reader = FakeVolumeReader()
    reader.directory("/D", [Entry.dir("A"), Entry.file("x", allocated: mib(1), fileID: 1)])
    reader.failing("/D/A", .permissionDenied)
    #expect(try reader.readDirectory(at: CanonicalPath("/D")!).map(\.name) == ["A", "x"])
    reader.reverseEntryOrder = true
    #expect(try reader.readDirectory(at: CanonicalPath("/D")!).map(\.name) == ["x", "A"])
    #expect(throws: DirectoryReadError.permissionDenied) { try reader.readDirectory(at: CanonicalPath("/D/A")!) }
    #expect(throws: DirectoryReadError.notFound) { try reader.readDirectory(at: CanonicalPath("/nope")!) }
    #expect(reader.readLog.map(\.raw) == ["/D", "/D", "/D/A", "/nope"])
}

@Test func fakeReaderDeviceFallsBackToNearestAncestor() throws {
    let reader = FakeVolumeReader(defaultDeviceID: 1)
    reader.device("/Volumes/ext", 9)
    #expect(try reader.deviceID(of: CanonicalPath("/Volumes/ext/a/b")!) == 9)
    #expect(try reader.deviceID(of: CanonicalPath("/Users")!) == 1)
}

@Test func fakeReaderMountFallsBackToNearestAncestor() throws {
    let reader = FakeVolumeReader(defaultMountPath: "/System/Volumes/Data")
    reader.mount("/", "/")
    reader.mount("/System/Volumes/Data", "/System/Volumes/Data")
    #expect(try reader.mountPath(of: CanonicalPath("/System/Library")!).raw == "/")
    #expect(try reader.mountPath(of: CanonicalPath("/System/Volumes/Data/Users/u")!).raw == "/System/Volumes/Data")
    #expect(try FakeVolumeReader().mountPath(of: CanonicalPath("/Users")!).raw == "/System/Volumes/Data")
}

@Test func fakeClockAdvancesByStep() {
    let clock = FakeClock(stepNanoseconds: 5)
    #expect(clock.now() == Instant(nanosecondsSince1970: 0))
    #expect(clock.now() == Instant(nanosecondsSince1970: 5))
}
