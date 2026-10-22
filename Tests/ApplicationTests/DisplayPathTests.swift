import Application
import SharedKernel
import Testing

@Test func displayPathStripsTheDataVolumePrefix() {
    #expect(DisplayPath.forReadPath(CanonicalPath("/System/Volumes/Data")!) == .root)
    #expect(DisplayPath.forReadPath(CanonicalPath("/System/Volumes/Data/Users/u")!).raw == "/Users/u")
    #expect(DisplayPath.forReadPath(CanonicalPath("/Users/x")!).raw == "/Users/x")
    #expect(DisplayPath.forReadPath(CanonicalPath("/System/Volumes/DataExtra")!).raw == "/System/Volumes/DataExtra")
}
