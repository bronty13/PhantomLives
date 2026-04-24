// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PurpleIRC",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PurpleIRC",
            path: "Sources/PurpleIRC"
        ),
        .testTarget(
            name: "PurpleIRCTests",
            dependencies: ["PurpleIRC"],
            path: "Tests/PurpleIRCTests"
        )
    ]
)
