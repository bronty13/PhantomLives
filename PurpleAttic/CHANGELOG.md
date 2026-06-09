# Changelog

All notable changes to PurpleAttic are documented here. This project follows
release-hygiene conventions from the repo root `CLAUDE.md`.

## [0.1.0] — 2026-06-08

Initial scaffold: the archival **engine** + the `pattic` CLI (the safe,
non-destructive half of PurpleAttic). The SwiftUI GUI and the guarded purge
stage come in later releases.

### Added
- **`PurpleAtticCore`** engine library:
  - `RetentionPolicy` — the pure, unit-tested keep/purge predicate. A photo is
    purge-eligible only when it is **both** older than `keepWindowDays`
    (default 365) **and** not pinned by a "Save" album, "save" keyword, or
    (optional) Favorite. Conservative by construction: when in doubt, keep.
  - `ArchiveProfile` / `ProfileStore` — Codable job description (library,
    destinations, formats, retention, purge toggle) persisted as JSON, shared
    by the CLI and the future GUI. Profiles are the reuse mechanism: a second
    Mac / iCloud account is just another profile with `purgeEnabled = false`.
  - `ExportPlan` — pure builder for the `osxphotos export …` argument vector
    (one pass for HEIC originals, one `--convert-to-jpeg` pass for the JPEG
    set). Always emits `--update` (incremental), `--sidecar XMP` + `--exiftool`
    (metadata embedded AND in sidecars), `--touch-file`, `--retry 3`.
  - `ExportEngine` — orchestrates export → rsync mirror (no `--delete`) →
    verify → Cryptomator-vault cloud copy, with a detailed log and a
    human-readable run report.
  - `VerifyService` — inventory (path + size) comparison of each mirror against
    the primary, with optional deep SHA-256. This is the evidence the future
    purge stage will require before deleting anything.
  - `AtticLogger` — timestamped, append-only logs under
    `~/Library/Logs/PurpleAttic/`; run reports under `~/Downloads/PurpleAttic/`.
  - `Tooling` — robust locator for `osxphotos` / `exiftool` / `rsync` that
    probes Homebrew + pipx locations (a Finder-launched app has a minimal PATH).
- **`pattic`** CLI: `doctor` (toolchain check), `init` (write a starter
  profile), `plan` (preview the osxphotos commands + retention, run nothing),
  `export` (run the archive; `--dry-run`, `--deep`). **The CLI never purges** —
  deletion is reserved for the guarded GUI.
- Tests: 14 passing (retention boundary/pinning cases, export-argv assertions).

### Notes
- Requires `osxphotos` (`pipx install osxphotos`) and `exiftool`
  (`brew install exiftool`) to run an export; `rsync` ships with macOS.
- Run host must have originals on disk ("Download Originals"); a host on
  "Optimize Mac Storage" should set `downloadMissingFromICloud: true`.
