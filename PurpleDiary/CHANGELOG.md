# Changelog

All notable changes to PurpleDiary are documented here.

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
- App-lock is UI-only this phase; the lock screen, passphrase/Keychain wiring,
  and SQLCipher encryption-at-rest are the next Phase-1 milestone (see
  SCOPING.md).
- App-lock is UI-only this phase; the lock screen, passphrase/Keychain wiring,
  and SQLCipher encryption-at-rest are the next Phase-1 milestone (see
  SCOPING.md).
