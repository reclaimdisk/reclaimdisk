import Application
import Darwin
import Foundation
@testable import Infrastructure
import SharedKernel
import Testing

private let reader = DarwinVolumeReader()
private let fourMiB = 4 * 1_048_576

private func entries(_ folder: TempFolder) throws -> [String: DirectoryEntry] {
    sync()
    return Dictionary(uniqueKeysWithValues: try reader.readDirectory(at: folder.path).map { ($0.name, $0) })
}

@Test func plainFileReportsAllocatedAndPrivateSize() throws {
    let folder = try TempFolder()
    try folder.writeRandom("plain.bin", bytes: fourMiB)
    let e = try #require(try entries(folder)["plain.bin"])
    #expect(e.type == .file)
    #expect(e.allocated == ByteCount(UInt64(fourMiB)))
    #expect(e.privateSize == ByteCount(UInt64(fourMiB)))
    #expect(e.linkCount == 1)
}

// Pins the verified behavior: private size ignores hard links.
@Test func hardLinksShareFileIDAndReportFullPrivateSize() throws {
    let folder = try TempFolder()
    try folder.writeRandom("hl.bin", bytes: fourMiB)
    try folder.hardLink("hl.bin", to: "hl2.bin")
    let all = try entries(folder)
    let a = try #require(all["hl.bin"]), b = try #require(all["hl2.bin"])
    #expect(a.fileID == b.fileID)
    #expect(a.linkCount == 2 && b.linkCount == 2)
    #expect(a.privateSize == ByteCount(UInt64(fourMiB)) && b.privateSize == ByteCount(UInt64(fourMiB)))
}

@Test func fullClonesShareCloneIDWithZeroPrivateSize() throws {
    let folder = try TempFolder()
    try folder.writeRandom("orig.bin", bytes: fourMiB)
    try folder.clone("orig.bin", to: "clone1.bin")
    try folder.clone("orig.bin", to: "clone2.bin")
    let all = try entries(folder)
    let group = ["orig.bin", "clone1.bin", "clone2.bin"].compactMap { all[$0] }
    #expect(group.count == 3)
    #expect(Set(group.map(\.cloneID)).count == 1)
    #expect(group.allSatisfy { $0.cloneRefCount == 3 && $0.privateSize == .zero })
}

@Test func partiallyRewrittenCloneReportsRewrittenBytesAsPrivate() throws {
    let folder = try TempFolder()
    try folder.writeRandom("part.bin", bytes: fourMiB)
    try folder.clone("part.bin", to: "part-clone.bin")
    try folder.overwriteStart(of: "part-clone.bin", bytes: 1_048_576)
    #expect(try entries(folder)["part-clone.bin"]?.privateSize == ByteCount(1_048_576))
}

@Test func symlinkIsReportedAndNeverFollowed() throws {
    let folder = try TempFolder()
    #expect(symlink("/etc", folder.child("to-etc").raw) == 0)
    let all = try entries(folder)
    #expect(all["to-etc"]?.type == .symlink)
    #expect(all.keys.sorted() == ["to-etc"])
    #expect(try reader.entryType(at: folder.child("to-etc")) == .symlink)
}

@Test func subdirectoryHasNoFileSizes() throws {
    let folder = try TempFolder()
    try folder.mkdir("sub")
    let e = try #require(try entries(folder)["sub"])
    #expect(e.type == .directory && e.allocated == .zero && e.linkCount == 0)
    #expect(try reader.entryType(at: folder.child("sub")) == .directory)
}

@Test func mountPointsAreFlagged() throws {
    let volumes = try reader.readDirectory(at: CanonicalPath("/System/Volumes")!)
    #expect(volumes.first { $0.name == "VM" }?.isMountPoint == true)
}

@Test func largeDirectoryIsReadAcrossSeveralBulkCalls() throws {
    let folder = try TempFolder()
    for i in 0..<5_000 { FileManager.default.createFile(atPath: folder.child("f\(i)").raw, contents: nil) }
    #expect(try reader.readDirectory(at: folder.path).count == 5_000)
}

@Test func lockedFolderIsPermissionDenied() throws {
    let folder = try TempFolder()
    try folder.mkdir("locked")
    #expect(chmod(folder.child("locked").raw, 0) == 0)
    defer { chmod(folder.child("locked").raw, 0o755) }
    #expect(throws: DirectoryReadError.permissionDenied) { try reader.readDirectory(at: folder.child("locked")) }
}

@Test func pathLongerThanPathMaxIsNameTooLong() throws {
    let folder = try TempFolder()
    let segment = String(repeating: "d", count: 200)
    var fds: [Int32] = [open(folder.path.raw, O_RDONLY | O_DIRECTORY)]
    var raw = folder.path.raw
    while raw.utf8.count <= 1_100 {
        #expect(mkdirat(fds.last!, segment, 0o755) == 0)
        fds.append(openat(fds.last!, segment, O_RDONLY | O_DIRECTORY))
        raw += "/" + segment
    }
    defer {   // remove the deep chain relative to open fds; absolute paths fail past PATH_MAX
        for index in stride(from: fds.count - 1, to: 0, by: -1) {
            close(fds[index])
            unlinkat(fds[index - 1], segment, AT_REMOVEDIR)
        }
        close(fds[0])
    }
    #expect(throws: DirectoryReadError.nameTooLong) { try reader.readDirectory(at: CanonicalPath(raw)!) }
}

@Test func oddNamesRoundTrip() throws {
    let folder = try TempFolder()
    try folder.writeRandom("line\nbreak", bytes: 10)
    try folder.writeRandom("🙂.txt", bytes: 10)
    #expect(Set(try entries(folder).keys) == ["line\nbreak", "🙂.txt"])
}

@Test func missingPathsAreNotFound() {
    let missing = CanonicalPath("/private/tmp/reclaimdisk-does-not-exist-\(UUID().uuidString)")!
    #expect(throws: DirectoryReadError.notFound) { try reader.readDirectory(at: missing) }
    #expect(throws: DirectoryReadError.notFound) { try reader.entryType(at: missing) }
}

@Test func dataVolumeCapacityIsConsistent() throws {
    let c = try reader.capacity(ofVolumeAt: CanonicalPath("/System/Volumes/Data")!)
    #expect(c.usedByVolume <= c.total)
    #expect(c.available <= c.total)
    #expect(c.availableForImportantUsage > .zero)   // not >= available: Apple doesn't promise that
}

@Test func tempFolderIsOnTheDataVolume() throws {
    let folder = try TempFolder()
    #expect(try reader.deviceID(of: folder.path) == reader.deviceID(of: CanonicalPath("/System/Volumes/Data")!))
}

// Final review, Important 3: stat's device id is shared by the System and Data volumes; the mount point is not.
@Test func mountPathSeparatesSystemFromData() throws {
    #expect(try reader.mountPath(of: CanonicalPath("/System/Library")!).raw == "/")
    #expect(try reader.mountPath(of: CanonicalPath("/Users")!).raw == "/System/Volumes/Data")
    let folder = try TempFolder()   // keep it alive: its deinit deletes the folder
    #expect(try reader.mountPath(of: folder.path).raw == "/System/Volumes/Data")
}

/// On APFS, statfs reports the whole container's use for every volume. Each volume's own use must be smaller.
@Test func capacityReportsEachVolumesOwnUse() throws {
    let data = try reader.capacity(ofVolumeAt: CanonicalPath("/System/Volumes/Data")!)
    #expect(data.usedByVolume.bytes < data.total.bytes - data.available.bytes)   // the System and Preboot volumes use space too
    if let vm = try? reader.capacity(ofVolumeAt: CanonicalPath("/System/Volumes/VM")!) {
        #expect(vm.usedByVolume < data.usedByVolume)
    }
}

@Test func interruptedReadsAreRetried() throws {
    var calls = 0
    let value = try DarwinVolumeReader.retryingInterrupted { () throws(DirectoryReadError) -> Int in
        calls += 1
        if calls < 3 { throw .other(errno: EINTR) }
        return 7
    }
    #expect(value == 7 && calls == 3)
}

@Test func retriesStopAtTheLimitAndOnOtherErrors() {
    var calls = 0
    #expect(throws: DirectoryReadError.other(errno: EINTR)) {
        try DarwinVolumeReader.retryingInterrupted(attempts: 4) { () throws(DirectoryReadError) -> Int in calls += 1; throw .other(errno: EINTR) }
    }
    #expect(calls == 4)
    calls = 0
    #expect(throws: DirectoryReadError.notPermitted) {
        try DarwinVolumeReader.retryingInterrupted { () throws(DirectoryReadError) -> Int in calls += 1; throw .notPermitted }
    }
    #expect(calls == 1)
}

@Test func cloudOnlyFoldersHaveTheirOwnError() {
    #expect(DarwinVolumeReader.error(for: EDEADLK) == .cloudOnly)
}

/// man 2 getattrlist: unsupported attributes are skipped, not packed, so only the length word comes back.
@Test func skippedSpaceUsedFallsBackToStatfs() {
    func used(_ bytes: [UInt8]) -> UInt64? { bytes.withUnsafeBytes { DarwinVolumeReader.spaceUsed(fromAttributes: $0) } }
    #expect(used([4, 0, 0, 0] + [UInt8](repeating: 0, count: 12)) == nil)
    #expect(used([12, 0, 0, 0, 0xD2, 0x04, 0, 0, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 4)) == 1234)
}
