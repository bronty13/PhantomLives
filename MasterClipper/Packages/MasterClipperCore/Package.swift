// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MasterClipperCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MasterClipperCore",
            targets: ["MasterClipperCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "MasterClipperCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
