# Changelog

All notable changes to PurpleArchive are documented here.

## [Unreleased]

### Phase 1a — engine core + full CLI (2026-06-06)

The testable heart of ArchiveKit, all provable via `swift test`.

- **Extraction** (`LibArchiveExtractor`): streaming, **zip-slip-safe** (rejects
  `../` escapes, de-roots absolute paths into the destination), restores
  permissions / mtimes / symlinks, password support, progress + cancellation.
- **Creation** (`LibArchiveWriter`): zip (**AES-256** via `zip:encryption=aes256`),
  tar, tar.gz / tar.bz2 / tar.xz / **tar.zst** (multithreaded `zstd:threads=0`),
  single-file `.zst`/`.gz`; `.DS_Store`/`__MACOSX` stripping.
- **Integrity test** (`verify`): reads every entry's data through libarchive.
- **Hashing** (`Hasher`, CryptoKit): md5/sha1/sha256/sha512, streamed (O(1) memory).
- **Models**: `ArchiveFormat` (+ extension inference), `CompressionOptions`,
  `ExtractOptions`, `ArchiveEntryTree` (directory tree for the GUI).
- **`ExtractCoordinator`**: bounded-concurrency batch runner (many archives across
  all cores; order-preserving, failure-isolating).
- **`ArchiveService`** facade — the single entry point for GUI + CLI.
- **`parc` CLI** (swift-argument-parser): `l` (+`--json`), `x`, `a`, `t`, `info`,
  `hash`, `versions`, with `bsdtar`-style aliases and auto-detected formats.
- Vendored libarchive's debug `fprintf` spew suppressed via a force-included
  `#undef DEBUG` prefix header (order-independent).
- **13 passing tests**: round-trip across all 6 writable formats, AES round-trip,
  wrong-password rejection, zip-slip, tree building, hash vectors, coordinator
  concurrency/ordering/isolation, batch extract.
- `run-tests.sh` wrapper (forces full-Xcode toolchain for XCTest under CLT).

### Phase 0 — vendoring foundation (2026-06-06)

The make-or-break integration risk, de-risked first.

- **Vendored libarchive 3.7.7** (`Vendor/CLibArchive`) — 131 library sources +
  a CMake-generated arm64 `config.h`, wrapped as a local SwiftPM package.
- **Vendored Zstandard 1.5.6** (`Vendor/CZstd`) — single-file amalgamation,
  multithreaded, statically compiled in.
- Compression filters wired and **verified at runtime**: zlib, bzip2, **xz/lzma**
  (vendored API headers + system `liblzma`), **zstd** (static). `parc l` lists
  `zip`, `tar.gz`, `tar.bz2`, `tar.zst`, and `tar.xz`.
- `ArchiveKit` engine framework: `ArchiveEntry` model, `ArchiveError`,
  `LibArchiveEngine.list(_:)`, `ZstdEngine` (compress/decompress + version).
- `parc` CLI harness (`l`, `version`).
- `Scripts/build-vendored.sh` — reproducible, SHA-256-pinned source regeneration.
- 3 passing tests (version link, zstd round-trip, system-zip listing).
- Proven: compiles arm64-clean, links Swift→libarchive→zstd/lzma/z/bz2/iconv,
  and codesigns under the hardened runtime.
