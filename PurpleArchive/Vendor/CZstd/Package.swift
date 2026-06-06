// swift-tools-version:5.9
import PackageDescription

/// Local SwiftPM package wrapping Zstandard 1.5.6.
///
/// `Sources/CZstd/zstd.c` is the single-file amalgamation produced by
/// `build/single_file_libs/create_single_file_library.sh` against
/// https://github.com/facebook/zstd tag v1.5.6. The public API headers
/// (`include/zstd.h`, `include/zstd_errors.h`) are copied verbatim from
/// the release `lib/` tree. See `PROVENANCE.md` for the tarball SHA-256
/// and the exact regeneration recipe (`Scripts/build-vendored.sh`).
///
/// `ZSTD_MULTITHREAD` activates libzstd's internal worker-thread pool so
/// `ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, 0)` scales compression
/// across every Apple-Silicon performance core — the headline perf story
/// for PurpleArchive's `.zst` / `.tar.zst` creation path.
let package = Package(
    name: "CZstd",
    products: [
        .library(name: "CZstd", targets: ["CZstd"]),
    ],
    targets: [
        .target(
            name: "CZstd",
            path: "Sources/CZstd",
            sources: ["zstd.c"],
            publicHeadersPath: "include",
            cSettings: [
                // NB: the amalgamation already `#define ZSTD_MULTITHREAD`s
                // itself, so we don't redefine it here (avoids -Wmacro-redefined).
                // The amalgamation guards the x86-64 BMI2 assembly behind
                // architecture macros; on arm64 it compiles the portable C
                // path. Disabling the inline asm decoder keeps the build
                // identical across Intel and Apple Silicon hosts.
                .define("ZSTD_DISABLE_ASM"),
            ]
        ),
    ]
)
