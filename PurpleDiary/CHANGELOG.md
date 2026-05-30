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

### Notes
- Scaffold was authored in a Linux CI container; an on-Mac
  `./build-app.sh` + `./run-tests.sh` pass is still required before this is
  considered build-verified.
- App-lock is UI-only this phase; the lock screen, passphrase/Keychain wiring,
  and SQLCipher encryption-at-rest are the next Phase-1 milestone (see
  SCOPING.md).
