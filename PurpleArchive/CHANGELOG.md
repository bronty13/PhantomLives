# Changelog

All notable changes to PurpleArchive are documented here.

## [Unreleased]

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
