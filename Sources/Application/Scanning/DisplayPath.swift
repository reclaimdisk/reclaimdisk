import SharedKernel

public enum DisplayPath {
    private static let dataVolume = "/System/Volumes/Data"

    /// "/System/Volumes/Data" -> "/", "/System/Volumes/Data/X..." -> "/X...", anything else unchanged.
    public static func forReadPath(_ path: CanonicalPath) -> CanonicalPath {
        if path.raw == dataVolume { return .root }
        if path.raw.hasPrefix(dataVolume + "/"), let mapped = CanonicalPath(String(path.raw.dropFirst(dataVolume.count))) {
            return mapped
        }
        return path
    }
}
