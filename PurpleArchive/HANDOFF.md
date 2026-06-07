# PurpleArchive — architecture handoff

Read this before non-trivial changes. PurpleArchive is a macOS-native
archive/unarchive utility: a SwiftUI app + a `parc` CLI, sharing one engine
(`ArchiveKit`), reading/creating every archive format from today and yesteryear,
Apple-Silicon-optimized. Free direct-download, **non-sandboxed**, Sparkle 2
auto-update (shipped). The feature set is **complete** — see Status below.

## Two build systems, one source tree

- **`Package.swift`** (SwiftPM) builds `ArchiveKit` + the `parc` CLI + engine
  tests. This is the fast dev path: `swift build`, `DEVELOPER_DIR=…/Xcode.app/…
  swift test` (XCTest needs full Xcode, not CLT).
- **`project.yml`** (XcodeGen → `PurpleArchive.xcodeproj`) builds the `.app` + the
  three app-extensions, with `ArchiveKit` as a shared **framework** embedded once
  and linked by the app + appex. `./build-app.sh` regenerates it each build.

Both reference the same `Sources/` and `Vendor/`. (PurpleIRC `Package.swift` +
PurpleMark `project.yml` patterns, combined.)

## Layers

```
SwiftUI app (Sources/PurpleArchive)   parc CLI (Sources/parc)   QL/Thumb/FinderSync appex
        \                              /                         /
         └──────── ArchiveService (Engine/ArchiveService.swift) ── the facade all call
                              |  routes by magic bytes / multi-volume resolution
   ┌──────────────────┬───────────────┬──────────────────┬─────────────────────┐
 UnrarEngine      PeelerEngine    LibArchiveEngine     ZstdEngine          (services)
 (all RAR, by     (legacy Mac:    /Writer/Extractor/   (fast MT .zst)   Encoding · Vault
  Rar!\x1a\x07)    sit/cpt/hqx/    Editor — ~95% of                      Recommender · Hasher
                   MacBinary)      modern formats)                       MultiVolume · AppleDouble
        |                |                |                  |
  Vendor/CUnrar    Vendor/CPeeler   Vendor/CLibArchive   Vendor/CZstd   + system zlib/bz2/lzma
  (unrar 7.1.6,    (peeler, MIT)    (libarchive 3.7.7)   (zstd 1.5.6,
   extract-only)                                          static)
```

- **Only `Backends/*.swift` touch C/C++.** Everything above sees Swift value types
  + `ArchiveService`. Adding/replacing a backend = a new `Backends/*.swift` +
  routing in `ArchiveService`; call sites never change.
- **RAR routing:** `ArchiveService` sends every RAR (detected by `Rar!\x1a\x07`
  magic) to `UnrarEngine` — unrar covers 100% incl. RAR5 + recovery record, which
  libarchive's reader can't fully open. **unrar is extract-only freeware: never
  use it to *create* RAR** (the license forbids it; PurpleArchive never offers it).
- **Legacy routing:** `.sit/.cpt/.hqx`/MacBinary → `PeelerEngine`; resource forks
  written as AppleDouble `._name`. peeler is AI-generated, so it is gated by
  `PeelerLegacyTests` against a committed corpus (216/216 data-fork MD5s).
- **Multi-volume:** `MultiVolume.swift` detects `.001/.002…` numeric splits and
  concatenates to a temp before reading; `ArchiveService.resolvingVolumes()` wraps
  list/extract/test.

## Engine services (Sources/ArchiveKit)

- `Encoding/EncodingDetector.swift` — valid-UTF8-authoritative + per-char scoring +
  script-consistency + CJK weight; live re-decode of garbled filenames, no
  re-extract. The big cross-platform differentiator.
- `Vault/PasswordVault.swift` — Keychain-backed password vault.
- `Recommender/` — `FormatRecommender`, `WindowsSafeNamer`, `Hasher`
  (MD5/SHA-1/256/512 via CryptoKit).
- `Backends/LibArchiveEditor.swift` — in-place edit (delete/rename/add): streams
  surviving entries into a fresh same-format archive, atomic-replaces the original.
  **`copyData` must use `archive_read_data`/`archive_write_data`** — the
  `*_data_block` offset API is libarchive disk-writer-only ("not supported" else).

## App layer (Sources/PurpleArchive)

- `App/PurpleArchiveApp.swift` — `@main`; WindowGroup(ContentView) + Settings.
- `App/AppDelegate.swift` — `WindowStateGuard.applyOnLaunch` +
  `BackupService.runOnLaunchIfDue` + `UpdaterController` (Sparkle).
- `App/Info.plist` — Sparkle keys (shared Purple* EdDSA), `CFBundleDocumentTypes`,
  `UTExportedTypeDeclarations` (legacy UTIs sit/cpt/hqx), and **`CFBundleIconFile`**
  (see App icon below).
- `Services/SettingsStore.swift` — Codable settings →
  `~/Library/Application Support/PurpleArchive/settings.json`; resolves backup +
  extract paths. Writes settings.json on first run (else the first backup no-ops).
- `Services/BackupService.swift` — auto-backup-on-launch (Timeliner pattern).
- `Services/WindowStateGuard.swift` — verbatim PhantomLives split-view guard.
- `ViewModels/AppModel.swift`, `ViewModels/JobQueue.swift` — open/extract/compress
  with progress (off-main engine calls); bounded-concurrency batch queue.
- `Views/` — `ContentView` (manual HStack sidebar, **NOT** NavigationSplitView;
  routes single vs multi drops), `SidebarView` (Open/Queue/Settings), `QueueView`,
  `ArchiveBrowserView` (Table + live encoding picker + edit + drag-out via lazy
  file-promise NSItemProvider), `CompressDropView`, `SettingsView`.

## App-extensions (Sources/PurpleArchive{QuickLook,Thumbnail,FinderSync})

- `PurpleArchiveQuickLook` — data-based `QLPreviewProvider` (note: the data-preview
  API is in **QuickLookUI**, not QuickLook). Spacebar preview of the entry tree.
- `PurpleArchiveThumbnail` — `QLThumbnailProvider`, content-aware Finder icon.
- `PurpleArchiveFinderSync` — `FIFinderSync`; **class renamed `ArchiveFinderSync`**
  to avoid clashing with the system `FinderSync` module. Right-click extract/compress.
- All three `import ArchiveKit`, link (not embed) the shared framework, and set
  `LD_RUNPATH` `@executable_path/../../../../Frameworks`. `build-app.sh` stamps the
  version into each appex plist and signs inside-out (frameworks → appex → app).

## Conventions

`build-app.sh` (build→stamp-plists→bundle `parc` to `Contents/Helpers/parc`→sign
inside-out→install), `install.sh` (hardened four-step freshness proof),
`run-tests.sh` (engine suite is the authoritative headless check; GUI-hosted app
tests hang headless — `SKIP_APP_TESTS=1`). Default user output →
`~/Downloads/PurpleArchive/`. Vendored sources committed; regenerate via
`Scripts/build-vendored.sh` (SHA-256-pinned; needs cmake `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`
for libarchive config.h). libarchive's debug `fprintf` spew is killed by
force-included `src/pa_prefix.h` (`#undef DEBUG`).

**App icon:** generated deterministically from `Scripts/generate-icon.swift` →
`iconutil` → `Contents/Resources/AppIcon.icns`, declared via `CFBundleIconFile`
in the source `Info.plist`. `build-app.sh` uses **set-or-add** (a bare `PlistBuddy
Set` silently no-ops on a missing key — that bug shipped no icon through v1.0.714).
Follows the repo-wide standard in `docs/app-icon-standard.md`.

## Release

Sparkle 2 is wired and shipping. Cut a release with sandbox **disabled** (the
login Keychain is unreadable sandboxed → false "profile not stored"):

```sh
NOTARY_APPLE_ID=robert.olen@icloud.com NOTARY_TEAM_ID=SRKV8T38CD \
NOTARY_PASSWORD=<app-specific-pw> ALLOW_DIRTY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/release.sh
```

`release.sh` supports INLINE notary creds because `notarytool store-credentials`
fails headless here ("User interaction is not allowed"). Builds a notarized,
stapled, Sparkle-signed DMG + updates `appcast.xml`. See `RELEASING.md`.

## Status (2026-06-06) — feature-complete

Reads/creates every modern format + 7z (libarchive's own writer, no p7zip), all
RAR (unrar), legacy Mac formats (peeler), multi-volume splits; encoding fix,
Keychain vault, recommender, convert, repair, hashing, in-place edit,
single-entry + drag-out extraction, batch queue, Quick Look + thumbnails + Finder
Sync, bundled `parc` CLI, Sparkle auto-update. Engine suite **44/44**.

**Last public release: 1.0.709.** Substantial work is unreleased on `main`
(legacy-format Quick Look, bundled CLI, USER_MANUAL, multi-volume, batch
queue/drag-out/visual polish, full RAR, the app-icon fix). Local build ≥ 1.0.718.
A release ships all of it — confirm a valid app-specific password first (a prior
one was advised rotated).

Nothing major is deferred. Possible future polish only: 7z is created via
libarchive (fine); GUI bits (queue, drag-out, Quick Look live render, Finder Sync
menu) can only be build/structure-verified headless — visual confirmation needs a
real desktop / VNC.
