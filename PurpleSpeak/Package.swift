// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PurpleSpeak",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PurpleSpeak",
            path: "Sources/PurpleSpeak",
            exclude: ["App/PurpleSpeak.entitlements"]
        ),
        .testTarget(
            name: "PurpleSpeakTests",
            dependencies: ["PurpleSpeak"],
            path: "Tests/PurpleSpeakTests"
        )
    ]
)
