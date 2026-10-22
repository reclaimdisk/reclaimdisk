/// A number of bytes on disk. Never negative.
public struct ByteCount: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let bytes: UInt64

    public init(_ bytes: UInt64) { self.bytes = bytes }

    public static let zero = ByteCount(0)
    public static let mebibyte = ByteCount(1_048_576)
    public static let gibibyte = ByteCount(1_073_741_824)

    public static func + (lhs: ByteCount, rhs: ByteCount) -> ByteCount { ByteCount(lhs.bytes + rhs.bytes) }
    public static func += (lhs: inout ByteCount, rhs: ByteCount) { lhs = lhs + rhs }
    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool { lhs.bytes < rhs.bytes }

    /// `self - other`, but never below zero.
    public func subtractingClamped(_ other: ByteCount) -> ByteCount {
        bytes > other.bytes ? ByteCount(bytes - other.bytes) : .zero
    }

    public var description: String { "\(bytes) B" }
}
