// swift-tools-version:5.9
import PackageDescription

/// Local SwiftPM package wrapping **RARLAB's unrar 7.1.6** for RAR/RAR5
/// extraction — the formats libarchive can't fully cover (notably RAR5 with a
/// recovery record) plus genuine recovery-record-assisted reading.
///
/// unrar is **extract-only freeware** (see `LICENSE`): usable to read RAR
/// archives, NOT to create them or reverse-engineer the algorithm. A thin C shim
/// (`cunrar.cpp` / `include/cunrar.h`) exposes a flat C API so Swift imports it
/// as a plain C module. Only the library translation units the upstream
/// `makefile` lists (OBJECTS + LIB_OBJ) are compiled; the rest are `#include`d
/// by those and excluded from the build. See `PROVENANCE.md`.
let package = Package(
    name: "CUnrar",
    products: [
        .library(name: "CUnrar", targets: ["CUnrar"]),
    ],
    targets: [
        .target(
            name: "CUnrar",
            path: "Sources/CUnrar",
            exclude: [
                // unrar .cpp files that are #included by other TUs, not compiled
                // standalone (everything outside the makefile's OBJECTS/LIB_OBJ).
                "unrar/arccmt.cpp", "unrar/blake2s_sse.cpp", "unrar/blake2sp.cpp",
                "unrar/cmdfilter.cpp", "unrar/cmdmix.cpp", "unrar/coder.cpp",
                "unrar/crypt1.cpp", "unrar/crypt2.cpp", "unrar/crypt3.cpp", "unrar/crypt5.cpp",
                "unrar/hardlinks.cpp", "unrar/isnt.cpp", "unrar/log.cpp", "unrar/model.cpp",
                "unrar/motw.cpp", "unrar/rarpch.cpp", "unrar/recvol.cpp", "unrar/recvol3.cpp",
                "unrar/recvol5.cpp", "unrar/rs.cpp", "unrar/suballoc.cpp", "unrar/threadmisc.cpp",
                "unrar/uicommon.cpp", "unrar/uiconsole.cpp", "unrar/uisilent.cpp",
                "unrar/ulinks.cpp", "unrar/unpack15.cpp", "unrar/unpack20.cpp",
                "unrar/unpack30.cpp", "unrar/unpack50.cpp", "unrar/unpack50frag.cpp",
                "unrar/unpack50mt.cpp", "unrar/unpackinline.cpp", "unrar/uowners.cpp",
                "unrar/win32acl.cpp", "unrar/win32lnk.cpp", "unrar/win32stm.cpp",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("RARDLL"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
                .headerSearchPath("unrar"),
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
