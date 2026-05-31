# PurpleDiary — Handoff / Architecture Snapshot

Engineer-facing orientation for anyone picking up PurpleDiary. Read this before
non-trivial changes. For the design brief and roadmap see `SCOPING.md`; for the
security model see `Docs/SECURITY.md`; for user-facing help see `USER_MANUAL.md`.

Last updated: 2026-05-31 (end of Phase-2 feature work: Insights, Export,
Trackers, Photos import).

---

## 1. What it is

A native macOS SwiftUI journaling app, **local-first and private**: one
SQLCipher-encrypted SQLite database on the Mac, no account, **no network code**
(see §6 — this is a hard product constraint, reaffirmed after a WeatherKit
experiment was deliberately rolled back). Modeled on `Timeliner/` and built to
PhantomLives conventions.

**Status:** Phase 1 complete (journal + privacy core). Phase 2 shipped:
Insights dashboard, Export (MD/HTML/PDF/JSON), Trackers + graphs, and media —
Photos import (auto-assembled day, browse any day / all-recent), filesystem
import of photos, **video, and audio**, and a full-size viewer (image / AVKit
video / compact audio player). Phase 3 shipped: **journals** (multiple +
hidden/locked, Option A visibility gate). Phase 4 shipped: **reflection** —
"On This Day" (entries from today's date in past years) + bundled writing
prompts (daily-rotating, shown on an empty entry). Phase 5 shipped: **templates**
(reusable scaffolds with date tokens, via the New Entry split-menu). Phase 6
shipped: **calendar heatmap** (days shaded by word count) + an opt-in **local
daily reminder** (`UNUserNotificationCenter`). Phase 7 shipped: **PDF & file
attachments** (PDFKit reader + first-page thumbnail; any file as a generic
attachment). Drawing/sketch was deferred — PencilKit isn't a native-macOS fit.
Phase 8 shipped: **importers** (PurpleDiary round-trip + Day One / Journey /
Diarium JSON → journals, via File → Import Journal…). Phase 9 (per-journal
encryption **vault**) roadmapped in `SCOPING.md`.
Deferred: Calendar import, Map view, sync. Weather/WeatherKit was built and
**reverted** — it required network egress (lat/long → Apple), which conflicts
with the no-network guarantee.

## 2. Build / test / run

```sh
./build-app.sh              # xcodegen → Release build in /tmp → sign → install to /Applications → relaunch
./build-app.sh --no-open    # build + install, no focus-stealing relaunch
./build-app.sh --no-install # build only
./run-tests.sh              # xcodebuild test → PurpleDiaryTests (70 tests)
```

- **Requires full Xcode** (not just CLT) and `xcodegen` on PATH. `build-app.sh`
  sets `DEVELOPER_DIR` to Xcode if needed.
- Version is git-derived: `CFBundleShortVersionString = 1.0.<commit-count>`,
  `CFBundleVersion = <count>.<short-sha>`, stamped into the built Info.plist
  post-build. Source Info.plist keeps `0.0.0` placeholders — don't edit them.
- `build-app.sh` re-signs the bundle and **passes `--entitlements`** (load-bearing
  — see §7). `install.sh` does the quit/replace/relaunch to `/Applications`.

## 3. Mental model

`AppState` (`App/AppState.swift`, `@MainActor ObservableObject`) is the single
source of truth and the only thing views talk to. Canonical data flow:

```
View → appState.someMutation() → DatabaseService.shared → appState.reload<Slice>()
```

`AppState` owns the published slices the UI binds to:
`entries`, `tags`, `people`, `tagsByEntry`, `peopleByEntry`, `trackerTags`,
`trackerValuesByEntry`, `attachmentCountByEntry`, `journals`,
`entryCountByJournal`, plus selection (`selectedSection`, `selectedEntryId`,
`selectedJournalId`, `unlockedHiddenJournalIds`) and the privacy/lock state
(`keyStore`, `appLocked`, `pendingRecoveryKey`, `dbUnrecoverable`).

**Journal filtering:** Timeline, Calendar, Search, and Insights read
`appState.visibleEntries` (not `entries`), which applies the active journal
filter (`selectedJournalId`, `nil` = All) and the hidden-journal gate (a hidden
journal's entries are excluded unless its id is in `unlockedHiddenJournalIds`,
populated for the session by `unlockHiddenJournal` via `BiometricAuthService`).
The rule is the pure, tested `AppState.entryIsVisible(…)`.

`reloadAll()` refetches every slice; `reloadEntries()` / `reloadTags()` /
`reloadPeople()` / `reloadTrackers()` are the narrower paths. Per-entry joins
(tags/people/tracker values/attachment counts) are rebuilt by `reloadJoins()`.

### AppState.init ordering (load-bearing — don't reorder casually)

1. `settingsStore.save()` — ensure `settings.json` exists (so the launch backup
   never archives an empty support dir).
2. Wire `DatabaseService.keyResolver` to the keystore's current key.
3. `bootstrapKeystoreIfNeeded()` — first-run DEK + 24-word recovery phrase
   (probed without building `DatabaseService.shared`, so the migration doesn't
   run before the backup below).
4. `BackupService.runOnLaunchIfDue` — **before** the SQLCipher migration, so an
   upgrade install's plaintext DB is captured as a safety net.
5. Build `DatabaseService.shared` (migrates plaintext→SQLCipher if needed, opens
   keyed) + `openKeyedDatabaseAndCheckHealth()`.
6. `markBootedAndMigrateRecoveryEnvelope()`.
7. Seed defaults / sample data, `reloadAll()`.
8. Engage lock screen if enabled; install lock-on-background observer.

## 4. Data model & migrations

GRDB records in `Models/`: `Entry` (now carries `journalId`), `Mood`, `Tag`
(+ `EntryTag`), `Person` (+ `EntryPerson`), `TrackerTag` (+ `TrackerValue`,
`TrackerKind`), `Journal`, `Attachment`
(+ `AttachmentThumb` projection — carries `kind`/`mimeType` so the strip can
badge video and the viewer can pick image-vs-player without paging the BLOB),
`AppSettings`. Attachments cover **photos, video, audio, PDF, and any file**:
each is an `attachments` row with `kind` = `"photo"`/`"video"`/`"audio"`/`"pdf"`/
`"file"` and the raw bytes in `data` (PDF stores a first-page thumbnail + page
count in `height`; audio/file have no thumbnail) — no schema change was needed
for any of them, so the migration set stayed frozen. **Inline media:** an
attachment can also be placed *within* the body via `![caption](pd-attachment://<id>)`
(`InlineMedia`); `MarkdownEditor`'s preview renders text/media segments in order
(`InlineMediaView`), and the same attachment still shows in the strip. Day One
import rewrites `dayone-moment://` refs into these inline refs in place.

Migrations live **only** in `DatabaseService.applyMigrations(to:)` (so tests run
the real migrator against an in-memory DB). They are **append-only and
immutable** — editing a shipped migration changes its GRDB hash and bricks every
encrypted install at launch. The frozen set is asserted by
`SecurityMiscTests.testShippedMigrationsAreFrozen`:

| Migration | Adds |
|---|---|
| `v1_initial` | `entries` (incl. nullable lat/long/place/weather columns reserved up front), `tags`, `entry_tags`, `people`, `entry_people` |
| `v2_trackers` | `tracker_tags`, `tracker_values` (cascade with entry + tracker) |
| `v3_attachments` | `attachments` (photo/video/audio BLOBs + thumbnail, cascade with entry) |
| `v4_journals` | `journals` (+ seeded default journal `Journal.defaultId`); adds NOT NULL `entries.journal_id` (existing rows back-fill to default via the column DEFAULT) + index. Hidden = app-level visibility only. |
| `v5_templates` | `templates` (reusable entry scaffolds; two starter templates seeded on first run by `seedDefaultTemplatesIfEmpty`). |

To change shipped schema/data: **add a new migration**, never edit an existing
one. Append its id to the frozen-set test deliberately.

Note: the `weather_summary` / `temperature_c` / `latitude` / `longitude` /
`place_name` columns exist on `entries` (from `v1_initial`) but are currently
**unused** — they were reserved for the auto-context features. No code writes
them today (the weather feature that would have was reverted).

## 5. Privacy core (encryption + lock)

Whole-DB encryption via **SQLCipher 4.6.1**, vendored under `Vendor/` alongside
a patched **GRDB** (its `CSQLite` re-exports the vendored `sqlite3.h` so GRDB's
symbols bind to SQLCipher, not system libsqlite3). `project.yml` lists
**SQLCipher before GRDB** — link order is load-bearing.

- **DEK**: 256-bit, generated on first launch, cached in the login Keychain
  (`KeychainStore`, service `com.bronty13.PurpleDiary`). `PRAGMA key` set on
  every connection via `DatabaseService.makeConfiguration()`.
- **Passphrase** (optional): PBKDF2-HMAC-SHA256 @ 300k wraps the DEK into
  `keystore.json`. **Recovery key**: 24-word BIP39 phrase wraps the DEK into
  `recovery_envelope.json` (shown once on first launch). `boot_state.json` is an
  anti-data-loss "ever-booted" marker.
- **App-lock**: `AppLockScreen` gates the UI (Touch ID / device password /
  passphrase via `BiometricAuthService`), lock-on-launch + lock-on-background,
  ⌘L. `RecoveryScreen` handles the key-lost case (enter recovery key / reset →
  old data quarantined, not deleted).

Files: `Crypto`, `KeyStore`, `KeychainStore`, `RecoveryKey`, `BIP39Wordlist`,
`BootState`, `BiometricAuthService`, `DatabaseService` (the SQLCipher wiring +
`migratePlaintextToSQLCipher`). Photos attachments are BLOBs inside the
encrypted DB, so they inherit encryption-at-rest with no extra crypto.

## 6. No network — a hard constraint

PurpleDiary makes **no network requests**. No account, server, telemetry,
update-check, or sync. `settings.json` is plaintext (prefs only, no journal
content); everything else with journal content is in the encrypted DB. Any
feature that would phone out (weather, cloud sync, AI calls) is out of scope
unless the privacy posture is explicitly revisited — a WeatherKit feature was
implemented and then rolled back precisely on these grounds. If you add a
feature, keep it offline.

## 7. Conventions & gotchas

- **Sidebar = manual `HStack`** (`Views/ContentView.swift` + `SidebarView`),
  never `NavigationSplitView` (per CLAUDE.md). `DetailRouterView` switches on
  `AppState.Section`. `WindowStateGuard` is wired from `AppDelegate`.
  (`.navigationTitle` on Insights/Trackers is effectively inert in this layout —
  harmless, not load-bearing.)
- **Auto-backup on launch** → `~/Downloads/PurpleDiary backup/` (5-min debounce,
  14-day retention, verify/restore). Full Settings → Backup UI. `BackupService`.
- **Default outputs** → `~/Downloads/PurpleDiary/` (exports). User-overridable +
  persisted.
- **TCC entitlements under Hardened Runtime** (the Photos gotcha — and the
  reason `build-app.sh` passes `--entitlements`): a Developer-ID app is
  hardened-runtime-signed, and TCC refuses to even *prompt* for a protected
  resource unless the binary carries the matching entitlement, **even when
  non-sandboxed**. Photos needs
  `com.apple.security.personal-information.photos-library` in
  `PurpleDiary.entitlements` **and** `NSPhotoLibraryUsageDescription` in
  Info.plist. The codesign re-sign in `build-app.sh` would strip entitlements if
  not given `--entitlements`. (Same rule applies to Calendar/Location/etc. if
  ever added.) See the repo memory `reference-macos-photokit-tcc-entitlement`.
- **Migrations immutable** (§4). **SQLCipher link order** (§5).

## 8. Tests (`Tests/PurpleDiaryTests/`, 128 total)

Migration round-trip + cascades + frozen-set guard; model Codable + word count +
`TrackerKind` formatting; `SearchService` ranking; `BackupService`
debounce/retention/verify; crypto (AES-GCM, PBKDF2), BIP39 recovery,
`KeyStore` unlock round-trips, SQLCipher at-rest (ciphertext on disk, wrong-key
rejection, plaintext→cipher migration); `StatsService` (totals/streaks/tracker
series); `ExportService` render paths (MD/HTML/JSON incl. escaping + schema v4);
`SecurityDocView` markdown parser; attachment CRUD/dedupe + thumb projection
(kind/mime) + fetch-by-id + `ImageProcessing` resize; `FileImportService`
classification (image/video/audio/unsupported) + image- and audio-from-file
build; `TextImportService` merge rule + Markdown/plain-text/RTF reading;
`AppState.entryIsEmpty` discard-empty-entry predicate; `Journal` data layer
(default + back-fill + move + delete-reassign) and `AppState.entryIsVisible`
journal-visibility predicate; `PromptService` daily rotation + bundled-JSON
decode and `OnThisDayService` month/day matching; `TemplateService` token
render + `Template` CRUD/seed; `CalendarHeatmap` level/opacity buckets +
`NotificationService` reminder time-clamp/body. PhotoKit live import,
video poster decoding, and AVKit playback are verified by hand (no headless TCC
/ no AVFoundation media fixture).

## 9. Where things live

```
Sources/PurpleDiary/
├── App/      PurpleDiaryApp, AppState, AppDelegate, AppMenuCommands, Version, Info.plist, entitlements
├── Models/   Entry, Mood, Tag, Person, TrackerTag, Journal, Template, Attachment, AppSettings
├── Services/ DatabaseService(+SQLCipher), BackupService, SearchService, SampleDataService,
│             ExportService, ImageProcessing, VideoProcessing, PhotosImportService,
│             FileImportService, TextImportService, ImportService, InlineMedia, PDFProcessing, PromptService,
│             OnThisDayService, TemplateService, CalendarHeatmap, NotificationService, StatsService, KeyStore,
│             KeychainStore, Crypto, RecoveryKey, BIP39Wordlist, BootState, BiometricAuthService,
│             WindowStateGuard
└── Views/    ContentView (HStack sidebar) + DetailRouterView, SidebarView, TimelineView,
              EntryEditorView, CalendarView, OnThisDayView, InsightsView, SearchView, PeopleView,
              TagsView, TrackersView, PhotoImportView, AttachmentViewerSheet, ExportSheet,
              TemplatesSheet, ImportSheet, AppLockScreen, RecoveryScreen, RecoveryKeySaveSheet, SecurityDocView, Settings/, Shared/
Vendor/       GRDB.swift + SQLCipher 4.6.1 (local SwiftPM packages)
Resources/Prompts.json   Bundled writing-prompt library (Phase 4)
Docs/SECURITY.md   Security & Privacy whitepaper (also rendered in-app via Help)
```
