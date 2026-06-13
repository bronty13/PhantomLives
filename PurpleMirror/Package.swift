// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PurpleMirror",
    platforms: [
        .macOS(.v14)   // MenuBarExtra(.window), SettingsLink, openWindow
    ],
    dependencies: [
        // Sparkle 2.x for in-app auto-updates. SPM ships an xcframework binary
        // target; build-app.sh copies the macOS slice into Contents/Frameworks/
        // and codesigns the nested XPC services + framework inside-out.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "PurpleMirror",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PurpleMirror"
        ),
        .testTarget(
            name: "PurpleMirrorTests",
            dependencies: ["PurpleMirror"],
            path: "Tests/PurpleMirrorTests"
        )
    ]
)
