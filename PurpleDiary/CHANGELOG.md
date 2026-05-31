# Changelog

All notable changes to PurpleDiary are documented here.

## [Unreleased] — Phase 2: Export (Markdown / HTML / PDF / JSON)

### Added
- **Whole-journal export** in four formats, via **File → Export Journal… (⇧⌘E)**
  and **Settings → General → Export**:
  - **Markdown** — one document, entries grouped by year → month, each with a
    metadata line (date · mood stars · #tags · people · place) and its body
    verbatim. Opens in any editor or note vault.
  - **HTML** — a self-contained, zero-dependency styled page (purple theme,
    inline CSS), entries as cards with mood stars and tag/person chips.
  - **PDF** — the same HTML paginated through an off-screen `WKWebView`
    (US-letter portrait), good for printing or archiving.
  - **JSON** — a versioned (`schemaVersion: 1`), round-trippable dump of every
    entry (with resolved tag names + linked person ids), plus the people roster.
    Lays the groundwork for the Phase-3 importer.
- `ExportService` — `@MainActor enum` with pure `renderMarkdown` / `renderHTML` /
  `encodeJSON` render functions and an `export(format:…:exportDir:)` dispatcher.
  Output lands in the resolved export directory (default
  `~/Downloads/PurpleDiary/`, user-overridable in Settings → General), as a
  stamped `PurpleDiary-Journal-YYYY-MM-DD-HHmmss.<ext>` file. All user content
  is HTML-escaped before embedding; bodies get a small inline-Markdown pass
  (bold/italic/code/line-breaks).
- `ExportSheet` — format picker, destination readout, progress, success +
  **Reveal in Finder**. Reachable from the File menu and from Settings → General
  (which also hosts the persistent export-directory picker).

### Notes
- Build-verified on macOS: clean Developer-ID Release build; **60/60 tests**
  (54 prior + 6 new `ExportService` tests covering Markdown content/grouping,
  self-contained HTML, HTML-escaping of `<script>`/`&`, JSON round-trip +
  schema version, empty-journal, and chronological year/month grouping). All
  four formats were exported from the running app against an 8-entry journal and
  inspected: the Markdown structure, the 8-article HTML, the schema-v1 JSON, and
  the PDF — visually confirmed rendering the purple-themed cards with gold mood
  stars and preserved line breaks (the PDF/`WKWebView` path the unit tests can't
  cover).

## [Unreleased] — Security & Privacy whitepaper + in-app viewer

### Added
- **`Docs/SECURITY.md` — a full Security & Privacy whitepaper.** A read-it-end-
  to-end trust document covering what PurpleDiary protects and how: the
  SQLCipher-encrypted database, the Keychain-held DEK, the optional passphrase
  wrap, the 24-word BIP39 recovery key, the plaintext→SQLCipher upgrade
  migration, the cryptographic-primitives table, and a "verify the claims"
  section with commands anyone can run. Tailored to PurpleDiary's **local-only,
  no-network, no-cloud** model (the whole "in transit / in iCloud" surface that
  PurpleLife's whitepaper covers simply doesn't exist here), and honest about
  limitations — notably that `settings.json` is plaintext (preferences only, no
  journal content) and that the recovery key is a bearer credential.
- **In-app whitepaper viewer.** **Help → Security & Privacy whitepaper…** opens
  a dedicated window (`SecurityDocView`) that renders the bundled `SECURITY.md`
  with a small hand-rolled Markdown block parser (headings, lists, numbered
  items, fenced code, dividers, inline bold/italic/code/links via
  `AttributedString`). The doc is copied into `Contents/Resources` by
  `project.yml` and loaded via `Bundle.main`, so the in-app text always matches
  the repo's canonical authoring copy.

### Notes
- Build-verified on macOS: clean Release build (Developer-ID-signed),
  **54/54 tests** (47 prior + 7 new `SecurityDocView` parser tests covering all
  heading levels, bullet/dash and numbered lists, dividers, verbatim fenced code
  blocks, paragraph-join, and a bundled-`SECURITY.md` parse check). The Help →
  Security & Privacy menu item was confirmed present and reachable; the rendered
  window was not screenshotted this round because the Mac was at the lock screen.

## [Unreleased] — Phase 2: Insights dashboard

### Added
- **Insights** sidebar section — a statistics dashboard built on Swift Charts
  over the entries you already have (no new permissions, no data collection):
  summary cards (total entries, total words, days journaled, average mood,
  current + longest writing streak), a **mood-over-time** line chart (daily
  average, rated entries only), **entries-per-month** and **words-per-month**
  bar charts, and a **tag-usage** breakdown colored by each tag. Empty-state
  when the journal has no entries yet.
- `StatsService` — pure, testable aggregation (totals, monthly buckets,
  daily-average mood series, tag counts, and consecutive-day streaks with an
  injectable calendar/reference date). Streak logic counts back from today and
  falls back to a run ending yesterday so an evening writer isn't punished.

### Notes
- Build-verified on macOS: clean Release build; **47/47 tests** (Phase-1's 39 +
  8 `StatsService` tests covering totals, average-mood-excludes-unset, monthly
  buckets, tag ordering, and all streak cases). Insights dashboard exercised
  visually against a 7-entry journal (7 entries / 137 words / 5 days / avg mood
  3.2, with the mood line + monthly bars rendering).

## [Unreleased] — Phase 1: privacy core (encryption-at-rest + app-lock)

### Added
- **Encryption at rest (SQLCipher).** The whole `diary.sqlite` is now
  SQLCipher-encrypted (AES-256). GRDB + SQLCipher 4.6.1 are vendored under
  `Vendor/` (SQLCipher before GRDB so its `sqlite3_*` symbols win at link time;
  GRDB's `CSQLite` re-exports the vendored header). Every connection sets
  `PRAGMA key`; with no key the build behaves like plain SQLite (the test path).
- **Plaintext→SQLCipher upgrade migration.** On the first launch after this
  ships, an existing plaintext DB is detected (SQLite magic-header probe) and
  copied into a keyed sibling via `sqlcipher_export()`, then atomically renamed.
  The launch backup runs *before* the migration so the plaintext state is
  captured as a safety net.
- **KeyStore + Keychain.** A 256-bit data-encryption key is generated on first
  launch and cached in the login Keychain (local-only — no iCloud/cloud). A
  `boot_state.json` "ever-booted" marker prevents minting a fresh key (and
  orphaning data) if the Keychain entry is lost out-of-band.
- **24-word BIP39 recovery key.** Shown on first launch (mandatory save sheet
  with a 3-word typeback) and stored only inside an encrypted
  `recovery_envelope.json`. Unlocks the DB if the Keychain entry is ever lost.
  Regenerate anytime in Settings → Security.
- **App-lock.** Optional lock screen (Touch ID / device password via
  `LocalAuthentication`, or passphrase), lock-on-launch, lock-on-background
  (focus loss), and a Lock PurpleDiary menu item (⌘L). Recovery screen for the
  key-lost case (enter recovery key, or reset — old data is quarantined, not
  deleted).
- **Optional passphrase** wrapping the DEK (set/change/remove in Settings →
  Security), independent of the recovery key.
- **Settings → Security** tab (replaces the old toggles-only Lock tab):
  encryption status, lock options, Touch-ID-only mode, passphrase management,
  recovery-key regeneration.
- **Sample-data facility (Settings → General):** "Add 100 Sample Entries"
  (bulk, one transaction, spread across ~120 days) and "Remove All Sample
  Entries", tracked precisely via `AppSettings.sampleDataIds` so removal only
  touches app-generated entries.
- New services: `Crypto`, `KeyStore`, `KeychainStore`, `RecoveryKey`,
  `BIP39Wordlist`, `BootState`, `BiometricAuthService`; new views
  `AppLockScreen`, `RecoveryScreen`, `RecoveryKeySaveSheet`.

### Changed
- `BackupService.verifyArchive` now opens the extracted DB with the live key so
  the "Test" button works on encrypted archives.

### Notes
- **Build-verified on macOS (2026-05-30).** `./run-tests.sh` → **37/37 passing**
  (16 prior + Crypto 4, RecoveryKey 8, KeyStore 4, AtRest 3, SampleData 2).
  `./build-app.sh` builds Release clean (no warnings), Developer-ID-signed.
  Exercised end-to-end on a real upgrade: an existing 7-entry plaintext
  `diary.sqlite` migrated to SQLCipher (on-disk header confirmed non-plaintext),
  the pre-migration plaintext DB was captured in the launch backup, the recovery
  sheet appeared, and after a relaunch the timeline read all 7 entries from the
  encrypted DB. Lock screen (⌘L) and Settings → Security verified visually.
- Decisions: SQLCipher whole-DB (per SCOPING §7) over column-wrapping; recovery
  is the user-held BIP39 key only (no iCloud/CloudKit DEK escrow), matching
  PurpleDiary's local-first ethos. `settings.json` stays plaintext (no journal
  content; only non-sensitive prefs).

## [Unreleased] — Phase 1 scaffold

### Added
- Initial project scaffold: SwiftUI + GRDB/SQLite macOS app modeled on
  Timeliner, following PhantomLives conventions (manual-HStack sidebar,
  launch-time auto-backup, git-derived versioning, XcodeGen build).
- **Data model** (`v1_initial` migration): `entries`, `tags`, `entry_tags`,
  `people`, `entry_people`. Entry carries Markdown body, mood (0–5), word
  count, and nullable Phase-2 auto-context columns (lat/long/place/weather/temp)
  created up front so no follow-up migration is needed.
- **Timeline view** — entries grouped by month with an inline Markdown editor
  (debounced autosave), mood stars, and tag chips.
- **Calendar view** — month grid; days with entries are dotted; click to jump
  to or create an entry on that day.
- **Search** — ranked across title / body / tags / people (`SearchService`).
- **People** and **Tags** management views; six default tags seeded on first
  launch.
- **BackupService** — launch-time auto-backup to `~/Downloads/PurpleDiary
  backup/`, 5-minute debounce, 14-day retention, verify + restore. Full
  Settings → Backup UI.
- **SampleDataService** — seeds four sample entries on first launch; restorable
  from Settings → General.
- **WindowStateGuard** — canonical split-view/window-state guard wired via
  `AppDelegate`.
- **Settings** — General, Appearance, Lock (toggles only this phase), Backup.
- Test suite: migrations + cascade, model Codable + word count, search
  ranking, backup debounce/retention/verify.

### Fixed
- **Empty first-launch backup.** `AppState.init` ran the launch backup before
  `DatabaseService.shared` was first touched, so on a brand-new install the
  support directory was still empty when the backup zipped it — producing a
  0-file archive (`zip: Nothing to do!`) on exactly the launch where a fresh
  migration runs. Now the database file and `settings.json` are materialized
  before `BackupService.runOnLaunchIfDue`, so the first backup contains a real
  `diary.sqlite`. Verified by simulating a fresh install: the first launch's
  archive now holds 4 files (DB + WAL/shm + settings) instead of 0.
- Silenced two "result of `try?` is unused" warnings on the `@discardableResult`
  `createEntry`/`createPerson` calls in `CalendarView`/`PeopleView` (`_ = try?`).

### Notes
- **Build-verified on macOS (2026-05-30).** `./run-tests.sh` → **16/16
  passing** (BackupService 5, Migration 3, Model 4, Search 4). `./build-app.sh`
  builds Release clean (no warnings), installs to `/Applications/PurpleDiary.app`,
  and launches. Functionally exercised end-to-end: `v1_initial` migration
  applies, 6 default tags + 4 sample entries seed on first launch, backup-on-
  launch and Run Backup Now both write valid zips to `~/Downloads/PurpleDiary
  backup/` (verified the archive's inner `diary.sqlite` round-trips its rows).
- App-lock was UI-only in the scaffold; the lock screen, passphrase/Keychain
  wiring, and SQLCipher encryption-at-rest landed in the privacy-core milestone
  above.
