// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SlackSucker",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SlackSucker",
            path: "Sources/SlackSucker"
        ),
        .testTarget(
            name: "SlackSuckerTests",
            dependencies: ["SlackSucker"],
            path: "Tests/SlackSuckerTests"
        )
    ]
)
