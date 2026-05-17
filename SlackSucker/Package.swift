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
            path: "Sources/SlackSucker",
            linkerSettings: [
                // Direct libsqlite3 access — see FileOrganizer's
                // chronologicalOrdering / slackUploadOrdering. Shelling
                // to /usr/bin/sqlite3 was fragile when slackdump left
                // a WAL/SHM pair around and produced silent empty
                // results.
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "SlackSuckerTests",
            dependencies: ["SlackSucker"],
            path: "Tests/SlackSuckerTests",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
