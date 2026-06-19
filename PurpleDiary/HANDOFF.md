# PurpleDiary — Handoff / Architecture Snapshot

Engineer-facing orientation for anyone picking up PurpleDiary. Read this before
non-trivial changes. For the design brief and roadmap see `SCOPING.md`; for the
security model see `Docs/SECURITY.md`; for user-facing help see `USER_MANUAL.md`.

Last updated: 2026-06-19 (added: 15-theme picker — `Theme` model + the
Appearance grid, selection derived by matching `(accentColorHex, colorScheme)`
with no new persisted field, signature default flipped to Purple Dark; the
in-app doc reader generalized from `SecurityDocView` → `MarkdownDocView`, now
serving **both** `Docs/SECURITY.md` and a bundled `USER_MANUAL.md` from Help;
USER_MANUAL + SECURITY whitepaper polished. Earlier: 2026-06-01 Phase 9 vault
complete — title/body + attachment sealing, create/unlock/manage UI,
paste-back-tolerant recovery; vault seal fails closed rather than falling back
to plaintext).

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
Scripts/release.sh          # cut a notarized DMG + GitHub release (see RELEASING.md)
```

- **Releasing:** `Scripts/release.sh` builds a notarized, stapled `.dmg` and
  publishes a `purplediary-v<version>` GitHub release. There is **no Sparkle / no
  in-app auto-update** — that would mean an `appcast.xml` HTTPS poll, i.e. the
  exact update-check egress §6 forbids. Updates are download-only (re-drag the
  newer DMG). Full process + one-time per-Mac setup in `RELEASING.md`.

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
| `v6_vault` | `journals.is_vault` + `vault_envelopes` (per-journal content key wrapped under passphrase **and** 24-word recovery key). Phase-9 vault crypto foundation. Transparent sealing data path wired (`DatabaseService` seals title+body on write / unseals on read for unlocked vaults; locked vaults gated from `visibleEntries` + export). Make-Vault / unlock / change-passphrase / remove UI shipped in the sidebar; app-lock re-seals vaults. Seals entry title+body **and attachment bytes** (data + thumbnails). |

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
- **Vaults (Phase 9, on top of the DEK)**: a journal flagged `is_vault` has each
  entry's title, body, **and attachment blobs** sealed under a per-journal content
  key (`VaultService`, `pdvlt1:` sentinel). CK is dual-wrapped in `vault_envelopes`
  under a passphrase **and** a fresh 24-word recovery key generated *for that
  vault* at creation (shown once: copy / save-to-file). CK is session-only,
  dropped on ⌘L. `DatabaseService` seals on write / unseals on read only when
  unlocked; locked vaults are gated from `visibleEntries` + export.
  `MakeVaultSheet` / `VaultUnlockSheet` / `ChangeVaultPassphraseSheet` drive it
  from the sidebar; both recovery fields accept a clean line / numbered list / a
  pasted-or-**Read-from-file** saved key via `RecoveryKey.candidatePhrases`.

Files: `Crypto`, `KeyStore`, `KeychainStore`, `RecoveryKey`, `BIP39Wordlist`,
`BootState`, `BiometricAuthService`, `VaultService`, `DatabaseService` (the
SQLCipher wiring + `migratePlaintextToSQLCipher` + vault seal/unseal). Non-vault
photo attachments are BLOBs inside the encrypted DB, so they inherit
encryption-at-rest with no extra crypto; vault attachments are additionally
CK-sealed.

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
- **Themes (`Models/Theme.swift`).** 15 presets, each a `(accentHex, scheme)`
  pair. The whole UI already reads its accent from `AppState.effectiveAccentColor`
  (→ `settings.accentColorHex`) and its mode from `settings.colorScheme`, so a
  theme is **not** a new piece of state: `applyTheme` just writes those two
  fields, and `selectedTheme` is *derived* by `Theme.matching(...)` — there is no
  stored `themeId` to drift, and the custom ColorPicker/Mode controls read as
  "Custom" (no match). The picker grid lives in `AppearanceSettingsTab`. Two
  gotchas baked in: (1) every theme's `(accentHex, scheme)` is unique
  (`ThemeTests`) or selection would be ambiguous; (2) the `AppState.settings`
  setter calls `objectWillChange.send()` — without it a theme change wouldn't
  repaint the main window live (the setter mutates the child `SettingsStore`, not
  `AppState`). The signature default (Purple Dark) is the `AppSettings` default
  (`accentColorHex "#7C5CFF"`, `colorScheme "dark"`) — a new install opens on it;
  existing installs keep their saved values.
- **In-app docs = `Views/MarkdownDocView.swift`** (was `SecurityDocView`). One
  small hand-rolled block parser renders **both** `Docs/SECURITY.md` and
  `USER_MANUAL.md`, each bundled into `Contents/Resources` by `project.yml` and
  opened from the **Help** menu (`security-doc` / `user-manual` `Window` scenes in
  `PurpleDiaryApp`). To add another in-app doc: bundle the `.md` in `project.yml`,
  add a `Window` scene + a Help `Button`. The parser is locked down by
  `MarkdownDocViewTests` (incl. a bundling sanity check for each doc).
- **The entry editor is `NSTextView`-backed, not SwiftUI `TextEditor`**
  (`Views/Shared/MarkdownEditor.swift`). The swap was forced by the **format
  toolbar**: `TextEditor` doesn't expose its selection, which the toolbar needs to
  wrap/prefix the selected text. `MarkdownTextView` (an `NSViewRepresentable`)
  carries the binding + native spellcheck + undo + plain-Markdown storage and
  hands its `NSTextView` to `MarkdownActions`; the actual string surgery lives in
  the pure, tested **`MarkdownFormat`** enum (wrap / linePrefixed / cleared). The
  inline-media preview, Import, and word count are unchanged. Pattern ported from
  `MusicJournal/Views/MarkdownEditor.swift`. **No underline button by design** —
  Markdown has none, and `<u>` would leak literal tags into preview/exports.
- **Timeline header + calendar thumbnails read existing data, not new fetches.**
  `JournalHeaderView` recomputes its stat strip from `visibleEntries` via
  `StatsService`/`OnThisDayService`/`attachmentCountByEntry` (no DB hit).
  `CalendarView` precomputes a `[dayStart: NSImage]` map once per visible month
  (rebuilt on month / journal-filter / attachment change) via the cheap
  `attachmentThumbs` projection — **don't** move that fetch into the per-cell body
  (it would hit the DB ~31× per redraw).
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

## 8. Tests (`Tests/PurpleDiaryTests/`, 186 total)

Migration round-trip + cascades + frozen-set guard; model Codable + word count +
`TrackerKind` formatting; `SearchService` ranking; `BackupService`
debounce/retention/verify; crypto (AES-GCM, PBKDF2), BIP39 recovery
(+ `candidatePhrases` paste-back extraction from a clean line / numbered list /
full saved-file-with-prose / garbage-rejected),
`KeyStore` unlock round-trips, SQLCipher at-rest (ciphertext on disk, wrong-key
rejection, plaintext→cipher migration); `StatsService` (totals/streaks/tracker
series); `ExportService` render paths (MD/HTML/JSON incl. escaping + schema v4);
`MarkdownDocView` markdown parser (+ each doc's bundling sanity check); the
**theme table** (`ThemeTests` — 15 themes, unique ids, unique `(accent, scheme)`
pairs, valid hex, signature = Purple Dark, `Theme.matching` round-trip + case-
insensitive hex + Custom/auto → nil, fresh-install default selects the
signature); attachment CRUD/dedupe + thumb projection
(kind/mime) + fetch-by-id + `ImageProcessing` resize; `FileImportService`
classification (image/video/audio/unsupported) + image- and audio-from-file
build; `TextImportService` merge rule + Markdown/plain-text/RTF reading;
`AppState.entryIsEmpty` discard-empty-entry predicate; `Journal` data layer
(default + back-fill + move + delete-reassign) and `AppState.entryIsVisible`
journal-visibility predicate; `PromptService` daily rotation + bundled-JSON
decode and `OnThisDayService` month/day matching; `TemplateService` token
render + `Template` CRUD/seed + **`TemplateLibrary`** (`TemplateLibraryTests` —
curated set size, unique names, seed-defaults a proper subset keeping the
originals, every body renders with no leftover tokens); the **editor format
transforms** (`MarkdownFormat` wrap / linePrefix / clear, `MarkdownFormatTests`);
`CalendarHeatmap` level/opacity buckets +
`NotificationService` reminder time-clamp/body; **vault crypto core**
(`VaultService` dual-wrap envelope, seal/unseal, session keys) and the **vault
data path** (`DatabaseService` seal-on-write/unseal-on-read, refuse-write-to-locked,
vault-aware moves, `sealEntries`/`unsealEntries` convert + the locked-vault
`entryIsVisible` gate) and **vault management** (`createVault` dual-wrap
verification guardrail, `changePassphrase` re-wrap, `removeVault` decrypt-in-place,
each with locked-state guards) and **attachment blob sealing** (`sealData`/
`unsealData`, seal-on-insert + refuse-locked, read-time decrypt, `rekeyAttachments`
convert/remove + per-entry move re-key). PhotoKit live import,
video poster decoding, and AVKit playback are verified by hand (no headless TCC
/ no AVFoundation media fixture).

## 9. Where things live

```
Sources/PurpleDiary/
├── App/      PurpleDiaryApp, AppState, AppDelegate, AppMenuCommands, Version, Info.plist, entitlements
├── Models/   Entry, Mood, Tag, Person, TrackerTag, Journal, Template, TemplateLibrary, Attachment, AppSettings, Theme
├── Services/ DatabaseService(+SQLCipher), BackupService, SearchService, SampleDataService,
│             ExportService, ImageProcessing, VideoProcessing, PhotosImportService,
│             FileImportService, TextImportService, ImportService, InlineMedia, PDFProcessing, PromptService,
│             OnThisDayService, TemplateService, CalendarHeatmap, NotificationService, VaultService, StatsService, KeyStore,
│             KeychainStore, Crypto, RecoveryKey, BIP39Wordlist, BootState, BiometricAuthService,
│             WindowStateGuard
└── Views/    ContentView (HStack sidebar) + DetailRouterView, SidebarView, TimelineView (+ JournalHeaderView stats strip),
              EntryEditorView, CalendarView (per-day photo thumbnails), OnThisDayView, InsightsView, SearchView, PeopleView,
              TagsView, TrackersView, PhotoImportView, AttachmentViewerSheet, ExportSheet,
              TemplatesSheet, ImportSheet, VaultSheets (Make/Unlock/ChangePassphrase), AppLockScreen, RecoveryScreen, RecoveryKeySaveSheet, MarkdownDocView, Settings/ (AppearanceSettingsTab = theme grid), Shared/
Vendor/       GRDB.swift + SQLCipher 4.6.1 (local SwiftPM packages)
Resources/Prompts.json   Bundled writing-prompt library (Phase 4)
Docs/SECURITY.md   Security & Privacy whitepaper (bundled as a resource; rendered in-app via Help → Security & Privacy whitepaper)
USER_MANUAL.md     User manual (repo root; bundled as a resource; rendered in-app via Help → PurpleDiary User Manual)
```
