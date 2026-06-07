# Changelog

All notable changes to PurpleArchive are documented here.

## [Unreleased]

### Batch queue, drag-out, single-entry extraction, visual polish (2026-06-06)

- **Single-entry extraction** (`ArchiveService.extractEntry` /
  `extractEntryToTemp`): stream one file out of an archive without unpacking the
  rest — also the long-deferred "huge-archive single-file pull".
- **Drag-out**: drag any file from the browser table to Finder and it's extracted
  on drop (lazy file-promise to a temp file).
- **Batch queue** (`JobQueue` + `QueueView`, new **Queue** sidebar tab): drop
  several archives and they extract concurrently, bounded to the core count, each
  with progress, cancel, and reveal-in-Finder; adjustable parallelism. Multi-
  archive drops now route here automatically.
- **Visual polish**: app-wide purple accent, refined sidebar (active-job badge,
  engine-version footer, cleaner selected state).
- New test: single-entry extract + drag-out temp helper. Engine suite 41/41.
  GUI interactions (drag-out, queue) verified by build/structure; visual confirm
  pending on a desktop session.

### Multi-volume / split archives (2026-06-06)

- **Raw split sets** (`.001`/`.002`/… — 7-Zip "split to volumes", `split`,
  download mirrors) are now transparent: `MultiVolume` detects the set from any
  member, reassembles the parts (streamed, flat memory) into a temp file, and
  `list`/`extract`/`test` operate on it normally. Open `movie.7z.003` and the
  whole thing just works. GUI drop-routing + CLI both handle them.
- Structured spanning (split-zip `.z01`, multi-part RAR `.partN`/`.rNN`) is
  intentionally out of scope — those aren't plain concatenations.
- `MultiVolumeTests`: detection from any part, false-positive guard, and a
  3-volume list+extract round-trip. Engine suite 40/40.

### Legacy-format Quick Look, bundled CLI, user manual (2026-06-06)

- **Quick Look + thumbnails for legacy Mac formats**: exported UTIs for
  `.sit`/`.cpt`/`.hqx` (macOS has no built-in types), added to the app's
  `UTExportedTypeDeclarations` and the Quick Look / Thumbnail extensions'
  supported types — so StuffIt/Compact Pro/BinHex archives now preview and
  thumbnail like the mainstream formats.
- **`parc` CLI bundled in the app** at `Contents/Helpers/parc` (self-contained
  SwiftPM build, hardened-runtime signed). Symlink it to PATH — see USER_MANUAL.
- **`USER_MANUAL.md`** — full guide to the app (browse/extract/compress/edit/
  encoding/vault/Settings), Finder integration, and every `parc` command.

### In-place archive editing (2026-06-06)

Add, rename, and delete entries inside an archive without a manual
extract-and-repack — the BetterZip-class feature.

- **`LibArchiveEditor`** / **`ArchiveService.edit(_:operations:)`**: streams every
  surviving entry (data + metadata, no disk extract) from the source into a fresh
  archive of the same format, applies the `EditOperation`s (delete / rename /
  add), appends new files, then **atomically replaces** the original. Reuses the
  read entry for the write header so untouched entries keep their perms / mtime /
  symlink exactly. Re-encrypts (zip AES-256) when a password is supplied.
- Read-only formats (RAR, legacy Mac, single-file .gz/.zst) refuse clearly.
- **GUI**: select rows in the browser → Delete; ➕ Add Files…; right-click →
  Rename…. **CLI**: `parc edit <archive> --delete p --rename old=new --add local=path`.
- 4 edit tests (delete+rename+add round-trip, tar.zst, read-only refusal);
  verified end-to-end via `parc`. Engine suite 39/39.

### Quick Look + Finder Sync extensions (2026-06-06)

Archives now preview, thumbnail, and right-click in Finder — powered by the same
ArchiveKit engine as the app.

- **ArchiveKit split into a shared framework** (embedded once, linked by the app
  + all three extensions — the PurpleMark pattern). GUI files now `import
  ArchiveKit`.
- **Quick Look preview** (`PurpleArchiveQuickLook`, data-based `QLPreviewProvider`):
  spacebar an archive → styled HTML listing of its contents (entry tree, sizes,
  encryption badges) with no extraction. Light/dark aware.
- **Quick Look thumbnail** (`PurpleArchiveThumbnail`, `QLThumbnailProvider`):
  content-aware purple archive-box icon badged with the file count.
- **Finder Sync** (`PurpleArchiveFinderSync`, `FIFinderSync`): right-click →
  Purple Archive → Extract Here / Compress to ZIP / TAR.ZST / 7z, run via the
  engine off the menu thread.
- `build-app.sh` version-stamps + signs all three appex inside-out (frameworks →
  appex → app); whole bundle deep-strict valid. Each appex links
  `@rpath/ArchiveKit.framework` (arm64).
- **Verified headless:** compile, embed, signatures, `NSExtension` declarations,
  framework linkage. **Needs a desktop to verify:** Launch Services registration
  + live preview/thumbnail/menu (no `pkd`/Finder in the build env).

### Release infrastructure — Sparkle 2 auto-update (2026-06-06)

PurpleArchive is now distributable + self-updating.

- **Sparkle 2** integrated: `UpdaterController`, a "Check for Updates…" menu item,
  `SUFeedURL` + the shared Purple\* `SUPublicEDKey` in Info.plist. `build-app.sh`
  signs Sparkle's XPCServices/Updater/Autoupdate inside-out (Developer ID,
  hardened runtime) — verified deep-strict valid.
- **`Scripts/release.sh`** (build → notarize → DMG → EdDSA-sign → GitHub release →
  appcast), **`appcast.xml`**, **`RELEASING.md`** — cloned from the PurpleMark
  release pattern, adapted (tag `purplearchive-v<version>`, feed URL, minimum
  macOS 13).
- App builds + signs with Developer ID; release from a Mac that has the shared
  `PurpleDedup-Notary` notarytool profile + Sparkle private key.

### Phase 2d — legacy Macintosh formats (StuffIt / Compact Pro / BinHex / MacBinary) (2026-06-06)

The formats libarchive can't read — now opening cleanly.

- **Vendored `peeler`** (MIT C99, `Vendor/CPeeler`) — StuffIt `.sit` (methods
  13/14/15), Compact Pro `.cpt`, BinHex `.hqx`, MacBinary `.bin`, and nested
  wraps (`.sit.hqx`, `.sit.bin`).
- **`PeelerEngine`** backend + `ArchiveService` routing (by header magic via
  `peel_detect`, extension fallback). `list`/`extract`/`info`/`test` all route
  legacy formats to peeler, modern ones to libarchive. Resource forks are
  written as AppleDouble (`._name`) sidecars (`AppleDouble.swift`, byte-matching
  peeler's CLI); classic-Mac `:` paths are mapped to POSIX.
- **Validated, not trusted on faith:** peeler is AI-generated, so it's gated by
  `PeelerLegacyTests` — extract the committed redistributable corpus
  (`Tests/ArchiveKitTests/LegacyCorpus/`) and byte-verify every data fork
  against ground-truth MD5s. At adoption the **full upstream corpus passed
  216/216 data-fork checksums across 22 archives** (StuffIt 4.5/6.5.1/7, Compact
  Pro 1.33/1.52, BinHex, MacBinary). Engine suite 36/36.
- GUI + `parc l/x/t/info` handle legacy formats transparently.

(Test corpus + library courtesy of github.com/pappadf/peeler and
github.com/ssokolow's StuffIt/DiskDoubler test-file repos.)

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
