import ArgumentParser
import SharedKernel

extension Kind: ExpressibleByArgument {
    public init?(argument: String) { self.init(rawValue: argument) }

    public static var allValueStrings: [String] { allCases.map(\.rawValue) }
}
