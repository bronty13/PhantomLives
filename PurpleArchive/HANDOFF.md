# PurpleArchive — architecture handoff

Read this before non-trivial changes. PurpleArchive is a macOS-native
archive/unarchive utility: a SwiftUI app + a `parc` CLI, sharing one engine
(`ArchiveKit`), aiming to read/create every format from today and yesteryear,
Apple-Silicon-optimized. Free direct-download, non-sandboxed, Sparkle (deferred).

## Two build systems, one source tree

- **`Package.swift`** (SwiftPM) builds `ArchiveKit` + the `parc` CLI + engine
  tests. This is the fast dev path: `swift build`, `swift test`.
- **`project.yml`** (XcodeGen → `PurpleArchive.xcodeproj`) builds the `.app`
  (and, later, the Quick Look / Thumbnail / Finder Sync app-extensions). It
  compiles `Sources/ArchiveKit` + `Sources/PurpleArchive` together and links the
  vendored SwiftPM packages. `./build-app.sh` regenerates it each build.

Both reference the same `Sources/` and `Vendor/`. (PurpleIRC `Package.swift` +
PurpleMark `project.yml` patterns, combined.)

## Layers

```
SwiftUI app (Sources/PurpleArchive)        parc CLI (Sources/parc)
        \                                   /
         ArchiveService  (Engine/ArchiveService.swift) ── the facade both call
                              |
   LibArchiveEngine.list/extract/verify · LibArchiveWriter.create · ZstdEngine
   Hasher · ArchiveEntryTree · ExtractCoordinator (bounded concurrency)
                              |
   Vendor/CLibArchive (libarchive 3.7.7)   Vendor/CZstd (zstd 1.5.6, static)
   + system zlib / bzip2 / liblzma
```

- **Only `Backends/LibArchive*.swift` + `ZstdEngine.swift` touch C.** Everything
  above sees Swift value types + `ArchiveService`.
- **Adding a backend** (XADMaster, unrar, 7z-write in later phases) = a new
  `Backends/*.swift` + routing in `ArchiveService`; call sites never change.

## App layer (Sources/PurpleArchive)

- `App/PurpleArchiveApp.swift` — `@main`; WindowGroup(ContentView) + Settings.
- `App/AppDelegate.swift` — `WindowStateGuard.applyOnLaunch` + `BackupService.runOnLaunchIfDue`.
- `Services/SettingsStore.swift` — Codable settings → `~/Library/Application Support/PurpleArchive/settings.json`; resolves backup + extract paths.
- `Services/BackupService.swift` — auto-backup-on-launch (Timeliner pattern): zip Application Support → `~/Downloads/PurpleArchive backup/`, 14-day retention, 5-min debounce.
- `Services/WindowStateGuard.swift` — verbatim PhantomLives split-view guard.
- `ViewModels/AppModel.swift` — open/extract/compress with progress; off-main engine calls.
- `Views/` — `ContentView` (manual HStack sidebar, NOT NavigationSplitView), `SidebarView`, `ArchiveBrowserView` (Table + Extract + password sheet), `CompressDropView` (drag-to-compress), `SettingsView` (General + Backup tabs).

## Conventions

`build-app.sh` (build→install→relaunch, git-derived `1.0.<commit-count>`),
`install.sh` (hardened four-step freshness proof), `run-tests.sh` (both suites;
forces full-Xcode toolchain for XCTest). Default user output →
`~/Downloads/PurpleArchive/`. Vendored sources committed; regenerate via
`Scripts/build-vendored.sh` (SHA-256-pinned; needs cmake for libarchive config.h).

## Roadmap

- **Phase 2:** XADMaster (legacy Mac: sit/cpt/hqx/…), unrar (RAR), encoding
  detection/override, Keychain vault, Quick Look + Thumbnail extensions,
  multi-volume, format recommender → split `ArchiveKit` into a framework target
  embedded by the appex (PurpleMark pattern).
- **Phase 3:** 7z creation (p7zip/lib7zip), Finder Sync, preview + in-place edit,
  batch queue UI, repair hints, streaming single-file extraction, `parc
  convert`/`recommend`.
- **Deferred:** Sparkle auto-update (wire during first release; needs
  `SPARKLE_PUBLIC_KEY`, `RELEASING.md`, `appcast.xml`, `Scripts/release.sh`).
