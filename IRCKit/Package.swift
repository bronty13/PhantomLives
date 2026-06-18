// swift-tools-version:5.9
import PackageDescription

// IRCKit — the UI-independent IRC wire engine shared by PhantomLives IRC apps
// (PurpleIRC and Ircle). Pure Foundation + Network: socket transport, the
// RFC 1459 / IRCv3 line parser, CAP/SASL negotiation, SOCKS5/HTTP-CONNECT
// proxying, and the connection-event fan-out enum. No SwiftUI, no AppKit.
let package = Package(
    name: "IRCKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IRCKit", targets: ["IRCKit"]),
    ],
    targets: [
        .target(
            name: "IRCKit",
            path: "Sources/IRCKit"
        ),
        .testTarget(
            name: "IRCKitTests",
            dependencies: ["IRCKit"],
            path: "Tests/IRCKitTests"
        ),
    ]
)
