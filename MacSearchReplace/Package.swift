// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSearchReplace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SnRCore",
            targets: ["SnRCore", "SnRSearch", "SnRReplace", "SnRArchive", "SnREncoding", "SnRScript"]
        ),
        .executable(
            name: "MacSearchReplace",
            targets: ["MacSearchReplaceApp"]
        ),
        .executable(
            name: "snr",
            targets: ["snr"]
        ),
    ],
    targets: [
        // MARK: - Core library targets

        .target(
            name: "SnRSearch",
            dependencies: ["SnREncoding"],
            path: "Packages/SnRCore/Sources/SnRSearch"
        ),
        .target(
            name: "SnRReplace",
            dependencies: ["SnREncoding", "SnRSearch"],
            path: "Packages/SnRCore/Sources/SnRReplace"
        ),
        .target(
            name: "SnRArchive",
            dependencies: ["SnRReplace", "SnREncoding"],
            path: "Packages/SnRCore/Sources/SnRArchive"
        ),
        .target(
            name: "SnRPDF",
            dependencies: ["SnRSearch"],
            path: "Packages/SnRCore/Sources/SnRPDF"
        ),
        .target(
            name: "SnREncoding",
            path: "Packages/SnRCore/Sources/SnREncoding"
        ),
        .target(
            name: "SnRScript",
            dependencies: ["SnRSearch", "SnRReplace"],
            path: "Packages/SnRCore/Sources/SnRScript"
        ),
        .target(
            name: "SnRCore",
            dependencies: ["SnRSearch", "SnRReplace", "SnRArchive", "SnRPDF", "SnREncoding", "SnRScript"],
            path: "Packages/SnRCore/Sources/SnRCore"
        ),

        // MARK: - Tests

        .testTarget(
            name: "SnRCoreTests",
            dependencies: ["SnRCore"],
            path: "Packages/SnRCore/Tests/SnRCoreTests"
        ),
        .testTarget(
            name: "SnRSearchTests",
            dependencies: ["SnRSearch"],
            path: "Packages/SnRCore/Tests/SnRSearchTests"
        ),
        .testTarget(
            name: "SnRReplaceTests",
            dependencies: ["SnRReplace"],
            path: "Packages/SnRCore/Tests/SnRReplaceTests"
        ),
        .testTarget(
            name: "SnREncodingTests",
            dependencies: ["SnREncoding"],
            path: "Packages/SnRCore/Tests/SnREncodingTests"
        ),
        .testTarget(
            name: "SnRScriptTests",
            dependencies: ["SnRScript"],
            path: "Packages/SnRCore/Tests/SnRScriptTests"
        ),

        // MARK: - Executables

        .executableTarget(
            name: "MacSearchReplaceApp",
            dependencies: ["SnRCore"],
            path: "Apps/MacSearchReplace/Sources"
        ),
        .executableTarget(
            name: "snr",
            dependencies: ["SnRCore"],
            path: "Apps/snr-cli/Sources"
        ),
    ]
)
