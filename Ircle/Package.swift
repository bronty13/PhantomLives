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
        // Sparkle 2.x for in-app auto-updates. SPM ships an xcframework binary
        // target; build-app.sh copies the macOS slice into Contents/Frameworks/
        // and codesigns each nested XPC service + the framework. See RELEASING.md.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Ircle",
            dependencies: [
                .product(name: "IRCKit", package: "IRCKit"),
                .product(name: "Sparkle", package: "Sparkle"),
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
