// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PurpleIRC",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Sparkle 2.x for in-app auto-updates. SPM ships an xcframework binary
        // target; build-app.sh copies the macOS slice into Contents/Frameworks/
        // and codesigns each nested XPC service + the framework alongside the
        // main bundle. See RELEASING.md for the EdDSA keypair / appcast setup.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "PurpleIRC",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PurpleIRC"
        ),
        .testTarget(
            name: "PurpleIRCTests",
            dependencies: ["PurpleIRC"],
            path: "Tests/PurpleIRCTests"
        )
    ]
)
