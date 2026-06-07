# Changelog

All notable changes to PurpleArchive are documented here.

## [Unreleased]

### Phase 3b — best-effort recovery (2026-06-06)

- **`recover`** / **`parc repair`**: salvage readable files from a damaged or
  truncated archive — extract every entry that reads cleanly, stop gracefully at
  the first fatal stream error, and report whether recovery was complete (e.g.
  "Partial recovery: salvaged 3 entries before corruption"). Verified salvaging
  3/6 files from a truncated tar. (Compressed-stream/zip truncation that can't be
  opened at all is reported as such — honest about the limits.)
- 1 recovery test; engine suite 34/34.

### Phase 3a — 7z creation + one-step convert (2026-06-06)

- **7z creation** — turns out libarchive ships `archive_write_set_format_7zip`
  (LZMA2), so 7z is now a first-class *create* format (GUI picker + `parc a
  out.7z`), no p7zip vendor needed. Round-trips through create/list/test/extract.
- **`convert`** — transcode an archive to another format in one step
  (`ArchiveService.convert`, `parc convert in.zip out.tar.zst`): extract to a
  temp dir then re-create, preserving the internal structure. Beats the manual
  extract-then-recompress dance.
- `ArchiveFormat.canCreate` is now always true. 2 new tests (7z round-trip,
  zip→7z→tar.zst convert chain); engine suite 33/33.

### Phase 2c — format recommender + Windows-safe naming (2026-06-06)

- **`FormatRecommender`**: suggests the best format from the payload + your
  constraints — ZIP for encryption/Windows-compat, TAR+xz for max compression,
  TAR+zstd as the speed/ratio default, and a store-fast path when contents are
  already compressed (media/office). Each with a one-line rationale.
- **`WindowsSafeNamer`**: sanitizes entry names so archives extract cleanly on
  Windows — reserved chars (`\ / : * ? " < > |`), device names (CON/PRN/NUL/
  COM1–9/LPT1–9), trailing dots/spaces. Opt-in `windowsSafeNames` on create.
- **GUI**: "Recommend" button + Windows-safe toggle in the compress view.
  **CLI**: `parc recommend [--windows|--encrypted|--max-compression]`,
  `parc a --windows-safe`.
- 10 new tests (recommender + namer); engine suite 32/32.

**RAR note:** RAR/RAR5 reading already works via libarchive's built-in readers
(active through `archive_read_support_format_all`). Full **unrar** vendoring (for
the long-tail of newest RAR5 compression/encryption) and **XADMaster** (legacy
Mac: StuffIt/Compact Pro/BinHex) are deferred — both are large C++/ObjC vendors
that can't be responsibly verified without sample archives + tooling unavailable
in the current build environment. They'll land when validatable.

### Phase 2b — Keychain password vault (2026-06-06)

Type an archive password once.

- **`PasswordVault`** protocol with a **`KeychainVault`** (macOS Keychain generic
  passwords, keyed by filename so a remembered password survives the archive
  moving) and an **`InMemoryVault`** (tests / headless fallback).
- **GUI**: encrypted-archive extract auto-fills from the Keychain; the password
  sheet offers "Remember in Keychain".
- **CLI**: `parc x --use-vault [--password …]` (auto-fills, remembers on
  success) and `parc vault list` / `parc vault forget <key>`.
- 3 vault tests; verified end-to-end (remember → auto-fill → forget). Engine
  suite 22/22.

### Phase 2a — filename-encoding fix (2026-06-06)

The #1 cross-platform pain point no other Mac tool nails: archives from
Windows/Linux store filenames in a legacy codepage with no UTF-8 flag, so a
naïve decode yields mojibake.

- **`EncodingDetector`**: scores raw entry-name bytes (kept on every
  `ArchiveEntry`) against UTF-8 + CP437/CP850, Shift-JIS/CP932/EUC-JP,
  GBK/Big5/EUC-KR, windows-1251/KOI8-R, windows-1252/Latin-1. Valid UTF-8 is
  authoritative; otherwise picks by **average per-character plausibility + a
  script-consistency bonus** (genuine names cluster in one script; mojibake
  sprays across blocks), with a CJK-ideograph tiebreak.
- **Live re-decode** (`ArchiveEntry.reDecoded(using:)`,
  `ArchiveService.list(_:encoding:)` / `detectEncoding`): switch the active
  encoding with no re-read of the archive.
- **GUI** encoding picker in the browser header (auto-detects on open, shows the
  guess in the status bar). **`parc l --encoding auto|utf8|cp437|shift-jis|…`**.
- 6 encoding tests (Shift-JIS, CP437, windows-1251, UTF-8 authority, re-decode).

### Phase 1b — SwiftUI app + build/install (2026-06-06)

The MVP `.app`: build + install + launch verified fresh on Apple Silicon.

- **XcodeGen `project.yml`** — `PurpleArchive` app target (compiles ArchiveKit +
  GUI together, links the vendored `CLibArchive`/`CZstd` packages) + test target.
- **SwiftUI GUI**: `ContentView` with a manual fixed-width **HStack sidebar**
  (NOT `NavigationSplitView`, per docs), `ArchiveBrowserView` (entry `Table`,
  Extract action, encrypted-password sheet), `CompressDropView` (drag-to-compress
  with format/level/password), window-wide drop routing (archive → browse, files
  → compress), `SettingsView` (General + **Backup** tabs).
- **Auto-backup-on-launch** (`BackupService`, Timeliner pattern) + full Settings
  → Backup UI (toggle, retention, folder picker, Back Up Now, recent list).
  Fixed a first-launch bug where an empty support dir made `zip` no-op; settings
  now persist on init.
- **`WindowStateGuard`** wired from `AppDelegate` (verbatim PhantomLives helper).
- Programmatic **app icon** (`Scripts/generate-icon.swift` — purple archive box).
- **`build-app.sh`** (build→install→relaunch, git-derived version, Developer-ID
  or ad-hoc signing) + **`install.sh`** (hardened four-step freshness proof).
  `run-tests.sh` now runs both the SwiftPM engine suite and the xcodebuild app
  suite.
- `HANDOFF.md` architecture snapshot.
- **Verified:** `Verified: PurpleArchive 1.0.693 running fresh` — built, installed
  to /Applications, launched, no crash.
- *Deferred to release:* Sparkle auto-update.

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
