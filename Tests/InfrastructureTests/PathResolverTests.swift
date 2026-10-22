import Application
import Foundation
import Infrastructure
import SharedKernel
import Testing

@Test func resolvesSymlinkedFolders() throws {
    #expect(try PathResolver.resolve("/tmp", currentDirectory: .root).raw == "/private/tmp")
}

@Test func resolvesDotAndDotDotAgainstTheCurrentDirectory() throws {
    let folder = try TempFolder()
    try folder.mkdir("a")
    try folder.mkdir("b")
    #expect(try PathResolver.resolve(".", currentDirectory: folder.path) == folder.path)
    #expect(try PathResolver.resolve("a/../b", currentDirectory: folder.path) == folder.child("b"))
}

@Test func missingPathThrowsNotFound() {
    #expect(throws: DirectoryReadError.notFound) {
        try PathResolver.resolve("/private/tmp/reclaimdisk-missing-\(UUID().uuidString)", currentDirectory: .root)
    }
}

@Test func homeDirectoryIsAResolvedFolder() throws {
    let home = PathResolver.homeDirectory()
    #expect(home != .root)
    #expect(try DarwinVolumeReader().entryType(at: home) == .directory)
}
