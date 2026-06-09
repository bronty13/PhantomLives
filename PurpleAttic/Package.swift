// swift-tools-version:5.10
import PackageDescription

// PurpleAttic — exports the macOS Photos library to a plain-file archive (osxphotos
// engine), keeps multiple verified copies, and (later, behind a guard) purges aged
// non-"Save" photos from Photos to keep the live library small. This package ships the
// engine as a library plus the `pattic` CLI front-end; the SwiftUI GUI is a later target
// that wraps the same PurpleAtticCore engine.
//
// Pinned to tools-version 5.10 (Swift 5 language mode) to match the rest of PhantomLives
// and avoid Swift 6 strict-concurrency churn in a CLI that is intentionally synchronous.
let package = Package(
    name: "PurpleAttic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PurpleAtticCore", targets: ["PurpleAtticCore"]),
        // CLI is named "pattic" (not "PurpleAttic") to avoid a case-insensitive APFS
        // collision with the future GUI product "PurpleAttic" — the exact trap PurpleDedup
        // documented (CLI "purplededup" vs GUI "PurpleDedup" linked to the same bin path).
        .executable(name: "pattic", targets: ["pattic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "PurpleAtticCore",
            path: "Sources/PurpleAtticCore"
        ),
        .executableTarget(
            name: "pattic",
            dependencies: [
                "PurpleAtticCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/pattic"
        ),
        .testTarget(
            name: "PurpleAtticCoreTests",
            dependencies: ["PurpleAtticCore"],
            path: "Tests/PurpleAtticCoreTests"
        ),
    ]
)
