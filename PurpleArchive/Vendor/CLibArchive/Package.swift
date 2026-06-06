// swift-tools-version:5.9
import PackageDescription

/// Local SwiftPM package wrapping libarchive 3.7.7 (BSD-2-Clause).
///
/// `Sources/CLibArchive/src/` is the verbatim `libarchive/` library tree
/// from the https://github.com/libarchive/libarchive v3.7.7 release
/// tarball, plus a `config.h` generated once by CMake for arm64 macOS
/// (see `Scripts/build-vendored.sh` / `PROVENANCE.md` for the exact
/// configure flags + tarball SHA-256). The CLI front-ends (bsdtar/bsdcpio
/// /bsdcat/bsdunzip) are deliberately NOT vendored — we only need the
/// library.
///
/// Compression-filter dependencies:
///   • zlib  / bzip2 — headers ship in the macOS SDK; linked system libs.
///   • lzma  (xz)    — no header in the SDK, so the liblzma *API headers*
///                     are vendored (`include_lzma/`, from xz 5.6.3) and the
///                     ubiquitous system `liblzma` (dyld shared cache) is
///                     linked. API is forward-compatible within 5.x.
///   • zstd          — statically vendored via the sibling `CZstd` package
///                     so we control the version and its multithreaded
///                     (`ZSTD_c_nbWorkers`) Apple-Silicon fast path.
let package = Package(
    name: "CLibArchive",
    products: [
        .library(name: "CLibArchive", targets: ["CLibArchive"]),
    ],
    dependencies: [
        .package(path: "../CZstd"),
    ],
    targets: [
        .target(
            name: "CLibArchive",
            dependencies: [
                .product(name: "CZstd", package: "CZstd"),
            ],
            path: "Sources/CLibArchive",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .define("PLATFORM_CONFIG_H", to: "\"config.h\""),
                .headerSearchPath("src"),
                .headerSearchPath("include_lzma"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("lzma"),
                .linkedLibrary("iconv"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
    ]
)
