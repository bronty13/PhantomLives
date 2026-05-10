// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PurpleDedup",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PurpleDedupCore", targets: ["PurpleDedupCore"]),
        .executable(name: "PurpleDedup", targets: ["PurpleDedupApp"]),
        // CLI is named "pdedup" rather than "purplededup" to avoid a case-insensitive
        // filesystem collision with the GUI product "PurpleDedup". On default APFS (case-
        // insensitive), the bin-path file PurpleDedup and purplededup are the same path
        // and whichever links last wins — the .app ended up shipping the CLI binary in
        // place of the GUI before this rename.
        .executable(name: "pdedup", targets: ["PurpleDedupCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Sparkle 2.x for in-app auto-updates. SPM ships an xcframework binary target;
        // build-app.sh copies the macOS slice into Contents/Frameworks/ and codesigns
        // each XPC service + framework alongside the main bundle.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "PurpleDedupCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/PurpleDedupCore"
        ),
        .executableTarget(
            name: "PurpleDedupApp",
            dependencies: [
                "PurpleDedupCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PurpleDedupApp"
        ),
        .executableTarget(
            name: "PurpleDedupCLI",
            dependencies: [
                "PurpleDedupCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/PurpleDedupCLI"
        ),
        .testTarget(
            name: "PurpleDedupCoreTests",
            dependencies: ["PurpleDedupCore"],
            path: "Tests/PurpleDedupCoreTests"
        ),
    ]
)
