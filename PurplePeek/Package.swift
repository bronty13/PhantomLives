// swift-tools-version:5.10
import PackageDescription

// PurplePeek — a macOS media-triage app. Browse/drag a folder, recursively discover
// photos/videos/audio, make per-item decisions (keep/skip, favorite, title, caption,
// keywords, albums), then batch-import photos+videos to the Photos library (audio is
// keep-exported to a folder instead). Decisions persist in a local SQLite store keyed
// by file path so a path can be revisited and only undecided items re-shown.
//
// Pinned to tools-version 5.10 (Swift 5 language mode) to match the rest of PhantomLives
// and avoid Swift 6 strict-concurrency churn.
let package = Package(
    name: "PurplePeek",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // GUI app. Built into a .app bundle by build-app.sh (SwiftUI WindowGroup needs a
        // real bundle / Info.plist to activate its UI).
        .executable(name: "PurplePeek", targets: ["PurplePeek"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "PurplePeek",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PurplePeek",
            linkerSettings: [
                // Linked up front (Phase 1) so a SwiftPM link failure surfaces on the very
                // first build, not in Phase 5 when the PhotoKit code lands.
                .linkedFramework("Photos"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Quartz"),
                .linkedFramework("ImageIO"),
            ]
        ),
        .testTarget(
            name: "PurplePeekTests",
            dependencies: [
                "PurplePeek",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/PurplePeekTests"
        ),
    ]
)
