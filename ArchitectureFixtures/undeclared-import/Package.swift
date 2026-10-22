// swift-tools-version: 6.2
// Planted violation: B imports A without declaring it. C depends on A, so A's module
// exists when B compiles, which is exactly the leak the explicit import check catches.
import PackageDescription

let package = Package(
    name: "UndeclaredImport",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "A"),
        .target(name: "B"),
        .target(name: "C", dependencies: ["A"]),
    ]
)
