// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

var swiftSettings: [SwiftSetting] = [
    .define("SQLITE_ENABLE_FTS5"),
]
var cSettings: [CSetting] = []
var dependencies: [PackageDescription.Package.Dependency] = [
    // Local PurpleLife vendored SQLCipher. CSQLite re-exports SQLCipher's
    // sqlite3.h so GRDB's compiled symbol bindings get tagged with this
    // local package's binary instead of libsqlite3.dylib. This is the
    // change that makes GRDB actually CALL into SQLCipher's
    // implementation at runtime — see PurpleLife's
    // Vendor/SQLCipher/PROVENANCE.md for context.
    .package(path: "../SQLCipher"),
]

// For Swift 5.8+
//swiftSettings.append(.enableUpcomingFeature("ExistentialAny"))

// Don't rely on those environment variables. They are ONLY testing conveniences:
// $ SQLITE_ENABLE_PREUPDATE_HOOK=1 make test_SPM
if ProcessInfo.processInfo.environment["SQLITE_ENABLE_PREUPDATE_HOOK"] == "1" {
    swiftSettings.append(.define("SQLITE_ENABLE_PREUPDATE_HOOK"))
    cSettings.append(.define("GRDB_SQLITE_ENABLE_PREUPDATE_HOOK"))
}

let package = Package(
    name: "GRDB",
    defaultLocalization: "en", // for tests
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13),
        .tvOS(.v11),
        .watchOS(.v4),
    ],
    products: [
        .library(name: "CSQLite", targets: ["CSQLite"]),
        .library(name: "GRDB", targets: ["GRDB"]),
        .library(name: "GRDB-dynamic", type: .dynamic, targets: ["GRDB"]),
    ],
    dependencies: dependencies,
    targets: [
        // CSQLite is now a regular C target whose only job is to
        // `#include "sqlite3.h"` from our vendored SQLCipher package.
        // Switching from `systemLibrary` to `target` (with a dep on
        // SQLCipher) is the key change: when GRDB compiles against
        // this CSQLite, the resulting two-level-namespace bindings
        // point at the SQLCipher target (which gets linked into the
        // same binary), NOT at libsqlite3.dylib.
        .target(
            name: "CSQLite",
            dependencies: ["SQLCipher"],
            path: "Sources/CSQLite",
            // shim.c is empty; we just need the target to be a real C
            // target so SwiftPM treats it as a regular module with a
            // proper umbrella, not a system library.
            sources: ["shim.c"],
            publicHeadersPath: ".",
            cSettings: cSettings),
        .target(
            name: "GRDB",
            dependencies: ["CSQLite"],
            path: "GRDB",
            resources: [.copy("PrivacyInfo.xcprivacy")],
            cSettings: cSettings,
            swiftSettings: swiftSettings),
    ],
    swiftLanguageVersions: [.v5]
)
