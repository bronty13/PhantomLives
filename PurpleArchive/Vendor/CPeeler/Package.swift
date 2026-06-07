// swift-tools-version:5.9
import PackageDescription

/// Local SwiftPM package wrapping **peeler** — a small MIT-licensed C99 library
/// for unpacking legacy Macintosh archive formats that libarchive doesn't know:
/// StuffIt (`.sit`, incl. methods 13/14/15), Compact Pro (`.cpt`), BinHex
/// (`.hqx`), and MacBinary (`.bin`).
///
/// Source: https://github.com/pappadf/peeler (see PROVENANCE.md for the pinned
/// commit). Verified against its own redistributable test corpus (StuffIt
/// 4.5/6.5.1/7, Compact Pro 1.33/1.52, BinHex, MacBinary) via PurpleArchive's
/// own test harness (`PeelerLegacyTests`) before adoption — peeler is
/// AI-generated, so we trust the byte-level round-trip checks, not the label.
let package = Package(
    name: "CPeeler",
    products: [
        .library(name: "CPeeler", targets: ["CPeeler"]),
    ],
    targets: [
        .target(
            name: "CPeeler",
            path: "Sources/CPeeler",
            publicHeadersPath: "include",
            cSettings: [
                // formats/*.c and the lib roots include "internal.h" / "peeler.h"
                // relative to the source root and the public include dir.
                .headerSearchPath("."),
                .headerSearchPath("include"),
            ]
        ),
    ]
)
