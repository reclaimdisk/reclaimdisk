// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReclaimDisk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "reclaimdisk", targets: ["CLI"]),
        .executable(name: "ReclaimDiskApp", targets: ["ReclaimDiskApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    ],
    targets: [
        // Domain targets: depend only on the shared kernel (enforced by scripts/check-architecture.swift; see docs/architecture.md).
        .target(name: "SharedKernel"),
        .target(name: "Inventory", dependencies: ["SharedKernel"]),
        .target(name: "Catalog", dependencies: ["SharedKernel"]),
        .target(name: "Cleanup", dependencies: ["SharedKernel"]),
        .target(name: "Ledger", dependencies: ["SharedKernel"]),
        // Application: use cases and the translations between contexts.
        .target(name: "Application", dependencies: ["SharedKernel", "Inventory", "Catalog", "Cleanup", "Ledger"]),
        .target(name: "Infrastructure", dependencies: ["SharedKernel", "Inventory", "Catalog", "Application"]),
        // Front ends.
        .executableTarget(
            name: "CLI",
            dependencies: [
                "SharedKernel", "Inventory", "Catalog", "Application", "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(name: "AppFeature", dependencies: ["SharedKernel", "Inventory", "Catalog", "Application", "Infrastructure"]),
        .executableTarget(name: "ReclaimDiskApp", dependencies: ["AppFeature"]),
        // Shared test fakes; only test targets may depend on it.
        .target(name: "TestSupport", dependencies: ["SharedKernel", "Inventory", "Catalog", "Application"]),
        .testTarget(name: "SharedKernelTests", dependencies: ["SharedKernel", "TestSupport"]),
        .testTarget(name: "InventoryTests", dependencies: ["Inventory", "SharedKernel", "TestSupport"]),
        .testTarget(name: "CatalogTests", dependencies: ["Catalog", "SharedKernel"]),
        .testTarget(name: "ApplicationTests", dependencies: ["Application", "Inventory", "Catalog", "SharedKernel", "TestSupport"]),
        .testTarget(name: "InfrastructureTests", dependencies: ["Infrastructure", "Application", "Catalog", "SharedKernel", "TestSupport"]),
        .testTarget(name: "CLITests", dependencies: ["CLI", "Application", "Inventory", "Catalog", "SharedKernel", "TestSupport"]),
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature", "Application", "Inventory", "Catalog", "SharedKernel", "TestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
