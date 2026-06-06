// swift-tools-version:5.9
import PackageDescription

/// PurpleArchive — SwiftPM package for the engine (`ArchiveKit`), the CLI
/// (`parc`), and their tests.
///
/// This package builds the cross-platform/headless parts of PurpleArchive and
/// is the fast path for `swift build` / `swift test` during development. The
/// macOS `.app`, the Quick Look / Thumbnail / Finder Sync extensions, and the
/// Sparkle integration are assembled by the XcodeGen `project.yml`, which
/// references the same `Sources/` and `Vendor/` packages. Two build systems,
/// one source tree (the PurpleIRC `Package.swift` + PurpleMark `project.yml`
/// pattern, combined).
let package = Package(
    name: "PurpleArchive",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ArchiveKit", targets: ["ArchiveKit"]),
        .executable(name: "parc", targets: ["parc"]),
    ],
    dependencies: [
        .package(path: "Vendor/CZstd"),
        .package(path: "Vendor/CLibArchive"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ArchiveKit",
            dependencies: [
                .product(name: "CLibArchive", package: "CLibArchive"),
                .product(name: "CZstd", package: "CZstd"),
            ],
            path: "Sources/ArchiveKit"
        ),
        .executableTarget(
            name: "parc",
            dependencies: [
                "ArchiveKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/parc"
        ),
        .testTarget(
            name: "ArchiveKitTests",
            dependencies: ["ArchiveKit"],
            path: "Tests/ArchiveKitTests"
        ),
    ]
)
