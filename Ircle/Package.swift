// swift-tools-version:5.9
import PackageDescription

// Ircle — a nostalgic recreation of the classic Mac OS Ircle IRC client, built
// on the shared IRCKit wire engine. SwiftUI macOS app; ships as a real .app
// bundle via build-app.sh (needed so UNUserNotificationCenter authorization
// works and the app gets a stable Launch Services / TCC identity).
let package = Package(
    name: "Ircle",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../IRCKit"),
    ],
    targets: [
        .executableTarget(
            name: "Ircle",
            dependencies: [
                .product(name: "IRCKit", package: "IRCKit"),
            ],
            path: "Sources/Ircle"
        ),
        .testTarget(
            name: "IrcleTests",
            dependencies: ["Ircle"],
            path: "Tests/IrcleTests"
        ),
    ]
)
