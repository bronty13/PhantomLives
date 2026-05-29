// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PurpleVoice",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PurpleVoice",
            path: "Sources/PurpleVoice",
            exclude: ["App/Info.plist"]
        ),
        .testTarget(
            name: "PurpleVoiceTests",
            dependencies: ["PurpleVoice"],
            path: "Tests/PurpleVoiceTests"
        )
    ]
)
