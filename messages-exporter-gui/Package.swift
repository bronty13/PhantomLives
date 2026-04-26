// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MessagesExporterGUI",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MessagesExporterGUI",
            path: "Sources/MessagesExporterGUI"
        ),
        .testTarget(
            name: "MessagesExporterGUITests",
            dependencies: ["MessagesExporterGUI"],
            path: "Tests/MessagesExporterGUITests"
        )
    ]
)
