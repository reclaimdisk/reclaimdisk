import SharedKernel

public enum EstimateError: Error, Equatable, Sendable {
    case freesMoreThanItTakesUp
    case unnamedTool
}

/// How many bytes a candidate might free, and why that number is believed.
/// There is no memberwise initializer: a measured estimate cannot free more than it takes up,
/// and a tool-reported estimate never claims "frees at least".
public struct Estimate: Hashable, Sendable {
    public enum Basis: Hashable, Sendable {
        case measured
        case toolReported(tool: String)
        case unknown
    }

    public let basis: Basis
    public let freesAtLeast: ByteCount?
    public let takesUp: ByteCount?
    public let reported: ByteCount?

    private init(basis: Basis, freesAtLeast: ByteCount?, takesUp: ByteCount?, reported: ByteCount?) {
        self.basis = basis
        self.freesAtLeast = freesAtLeast
        self.takesUp = takesUp
        self.reported = reported
    }

    public static func measured(freesAtLeast: ByteCount, takesUp: ByteCount) throws(EstimateError) -> Estimate {
        guard freesAtLeast <= takesUp else { throw .freesMoreThanItTakesUp }
        return Estimate(basis: .measured, freesAtLeast: freesAtLeast, takesUp: takesUp, reported: nil)
    }

    /// `freesAtLeast` and `takesUp` stay nil: a tool's own number is not a promise of what deletion returns.
    public static func toolReported(tool: String, size: ByteCount) throws(EstimateError) -> Estimate {
        guard !BlankText.isBlank(tool) else { throw .unnamedTool }
        return Estimate(basis: .toolReported(tool: tool), freesAtLeast: nil, takesUp: nil, reported: size)
    }

    public static let unknown = Estimate(basis: .unknown, freesAtLeast: nil, takesUp: nil, reported: nil)
}
