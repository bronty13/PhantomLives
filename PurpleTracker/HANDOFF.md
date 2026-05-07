# HANDOFF — PurpleTracker

This document is a quick orientation for anyone (human or agent) picking up
PurpleTracker maintenance.

## What it is

A native macOS SwiftUI app that assigns a Matter ID
(`YYYY-MM-DD-#####`) to every unit of work and tracks type, status, time,
attachments (with hashes), notes, file-store paths, external refs, exports,
and runs an auto-backup on every launch. Built on Swift 5.10 + SwiftUI +
GRDB 6 + XcodeGen, targets macOS 14, modeled directly on the sibling
`Timeliner/` subproject.

## Repository layout

```
PurpleTracker/
  project.yml                     # XcodeGen — single source of truth for the project
  build-app.sh  run-tests.sh      # bash wrappers around xcodebuild
  Vendor/GRDB/                    # vendored GRDB 6.29.3 (see "Why vendored" below)
  Sources/PurpleTracker/
    App/                          # @main, AppState, Info.plist, entitlements, Version
    Models/                       # Matter, MatterType, MatterStatus, Attachment,
                                  # TimeEntry, Note, Cadence, AppSettings, ColorHex
    Services/                     # Database, MatterID, Backup, Attachment,
                                  # FileStore, Timer, Cadence, Export
    Views/
      Sidebar/  MatterList/  MatterDetail/  Time/  Settings/  Shared/
    Resources/Assets.xcassets/    # AppIcon + AccentColor
  Tests/PurpleTrackerTests/       # 8 XCTest classes, 22 tests
  README.md  USER_MANUAL.md  INSTALL.md  CHANGELOG.md  HANDOFF.md
```

## Build & test

```sh
xcodegen generate
./run-tests.sh        # 22 tests, ~1 s
./build-app.sh        # produces ./PurpleTracker.app
open ./PurpleTracker.app
```

The app is ad-hoc signed unless a Developer ID is present in the keychain.

## Key invariants

1. **Matter ID allocation is transactional.** `MatterIDService.allocateAndInsert`
   runs the counter advance and the matter insert inside the same GRDB write
   transaction. A failed insert releases the sequence — there are no gaps
   within a day. Tested in `MatterIDServiceTests.swift`
   (`testRollbackReleasesSequence`).

2. **Status auto-bump keys off lifecycle position, not name.**
   `AppState.bumpToInProgressIfNew` checks `statusValues[0].name` for the
   matter's current status and advances to `statusValues[1].name`. Renaming
   "New" → "Open" or "In-Progress" → "Active" is safe.

3. **Cadence terminal trigger keys off the last lifecycle value.**
   `AppState.updateMatterStatus` calls `CadenceService.spawnNext` when the
   new status equals `statusValues.last?.name`. Renaming "Closed" is safe.

4. **Attachment integrity uses SHA1.** MD5/SHA1/SHA256 are all stored at
   ingest, but `AttachmentService.verify(_:)` only recomputes SHA1 (per the
   user spec). Mismatch sets `last_verify_ok = false` and the row shows red.

5. **Auto-backup runs on launch, debounced to 5 minutes.** `BackupService`
   honours the PhantomLives standard from `../CLAUDE.md`. Default retention
   is **30 days** (overrides the standard's 14 per user spec); `0` = forever.

## Important files (where to look first)

| Concern                       | File                                                    |
|-------------------------------|---------------------------------------------------------|
| Schema & migrations           | `Sources/PurpleTracker/Services/DatabaseService.swift`  |
| Matter ID allocator           | `Sources/PurpleTracker/Services/MatterIDService.swift`  |
| App-state root + auto-backup  | `Sources/PurpleTracker/App/AppState.swift`              |
| Type/status seeds             | `DatabaseService.seedDefaults`                          |
| Backup format & retention     | `Sources/PurpleTracker/Services/BackupService.swift`    |
| Cadence factory               | `Sources/PurpleTracker/Services/CadenceService.swift`   |
| Spell-checked editor          | `Sources/PurpleTracker/Views/Shared/SpellCheckTextEditor.swift` |
| DOCX/PDF/MD export            | `Sources/PurpleTracker/Services/ExportService.swift`    |
| Matter ID badge (large + copy)| `Sources/PurpleTracker/Views/MatterDetail/Components/MatterIDBadge.swift` |

## Test suite

8 XCTest classes, 22 tests, all `@MainActor` (services that touch
`AppSettings`/UI state are `@MainActor`-isolated).

| File                          | What it covers                                           |
|-------------------------------|----------------------------------------------------------|
| `MigrationTests`              | v1 creates all tables; second `applyMigrations` is a no-op |
| `MatterIDServiceTests`        | padding, sequential, daily reset, rollback releases seq  |
| `AttachmentHashTests`         | RFC vectors for MD5/SHA1/SHA256 (empty + "abc"); verify mismatch |
| `CadenceServiceTests`         | each cadence kind + custom; copy/reset rules             |
| `BackupServiceTests`          | dir auto-create, retention trim, retention=0, list newest-first |
| `FileStoreServiceTests`       | template render, sanitisation                             |
| `ExportServiceTests`          | md/pdf/docx/clipboard smoke + brief format               |
| `StatusLifecycleTests`        | first time entry on "New" → "In-Progress"                |

## Why GRDB is vendored

The local Xcode toolchain forces `safe.bareRepository=explicit` on its child
`git` invocations (visible via `xcrun git config --list --show-origin`),
which makes SPM's bare-repo cache unusable on this machine. The workaround
is a shallow clone of GRDB at `Vendor/GRDB` referenced via a `path:` package
in `project.yml`. To bump the version: replace `Vendor/GRDB` with a fresh
shallow clone at the desired tag and re-run `xcodegen generate`.

## Known follow-ups & non-goals

- **Icon** — `Resources/Assets.xcassets/AppIcon.appiconset` ships with the
  generator script's purple "PT" placeholder. Run
  `swift Scripts/generate-icon.swift` to regenerate, or swap in a designed icon.
- **Notarisation** — out of scope for 1.0.0 (ad-hoc signed). To notarise,
  set up a Developer ID in the keychain; `build-app.sh` will pick it up.
- **iCloud/sync** — not implemented; everything lives in the local SQLite.
  Backups go to `~/Downloads/` so they're naturally swept up by Time Machine.
- **Attachment streaming** — attachments are read fully into memory for
  hashing and BLOB storage. Acceptable for the typical office-document use
  case; a streaming hasher would be needed for very large attachments.

## Releasing

The PhantomLives release-hygiene checklist applies:

1. Bump `Version.swift` to `1.0.x`.
2. Update `CHANGELOG.md`.
3. `./run-tests.sh` must pass.
4. `./build-app.sh` must succeed and the produced `.app` must launch.
5. Commit from the PhantomLives outer repo as a single subproject add.
