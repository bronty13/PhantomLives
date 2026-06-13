// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PurpleMirror",
    platforms: [
        .macOS(.v14)   // MenuBarExtra(.window), SettingsLink, openWindow
    ],
    targets: [
        .executableTarget(
            name: "PurpleMirror",
            path: "Sources/PurpleMirror"
        ),
        .testTarget(
            name: "PurpleMirrorTests",
            dependencies: ["PurpleMirror"],
            path: "Tests/PurpleMirrorTests"
        )
    ]
)
