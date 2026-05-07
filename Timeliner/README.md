# Timeliner

A native macOS SwiftUI app for organizing, visualizing, and sharing case
timelines. Built for true-crime enthusiasts (or anyone who wants to track a
chronologically structured story) — fully offline, single-user, with a
local SQLite database and a polished customizable UI.

## At a glance

- **Cases** with status (active / cold / closed) and pinning
- **Events** per case with date (or date range), markdown description,
  source URL, and a four-level importance indicator
- **Tags** with custom colors and per-event tagging (six built-in tags
  seeded on first launch)
- **People / persons of interest** with six built-in role chips
  (suspect, victim, witness, attorney, detective, other) and per-event
  linking
- **Vertical chronological timeline** grouped by year and month with
  date / tag / importance / text filters
- **Horizontal pan/zoom timeline** — Canvas-rendered, drag-to-pan,
  scroll/magnify-to-zoom, click a dot to edit, double-click empty
  space to add an event at that point in time
- **Cross-case combined timeline** — pick any subset of cases, see their
  events merged on one horizontal axis, color-coded per case
- **Cross-case search** ranked title-prefix > title-substring > body
  match across cases, events, people, and tags
- **Attachments** — image / PDF / arbitrary files attached to cases,
  events, or people. Stored as BLOBs in the database so they're carried
  by every backup. 25 MB per-file cap, image thumbnails generated
  automatically.
- **Standalone HTML export** — one self-contained file per case (CSS + JS
  inlined, no external dependencies) dropped at `~/Downloads/Timeliner/`
- **PDF export** — same HTML pipeline rendered through `WKWebView` and
  paginated to US-letter
- **Auto-backup at every launch** — zips the entire support directory
  (database, settings, attachments) into `~/Downloads/Timeliner backup/`
  with retention trimming. Verify and restore from the Settings →
  Backup tab.
- **Anniversary reminders** — opt-in `UNUserNotificationCenter` calendar
  reminders fired on the date-anniversary of important events. Floor
  by importance, lookahead window, and notification hour are all
  configurable.
- **Themes** — six built-in themes (Default, Midnight, Ocean, Forest,
  Sunset, Rose) plus a full custom-theme builder with live preview
- **Font customization** — per-slot (event title, event body, date
  column, sidebar) family / size / weight overrides
- **Sample cases shipped with the app** — three curated true-crime
  timelines drawn from public reporting and court records:
  *Murder of Madeline Soto* (150 events, 43 people),
  *Murder of Harmony Montgomery* (42 events, 28 people, body never
  recovered), and *Murder of Athena Strand* (22 events, 26 people,
  per-event source URLs). All seed on first launch so the app isn't
  empty for new users. Delete them any time; **Settings → General →
  Restore Sample Data** brings the canonical versions back.

## Build

```sh
./build-app.sh   # produces ./Timeliner.app
```

The build script:
- Regenerates `Timeliner.xcodeproj` via `xcodegen` from `project.yml`
- Generates the app icon programmatically via `Scripts/generate-icon.swift`
- Builds in Release config in `/tmp` (avoids iCloud Drive xattr issues)
- Signs with the user's Developer ID Application certificate if present,
  ad-hoc otherwise

Version is auto-derived from git: `1.0.<commit-count>` for
`CFBundleShortVersionString` and `<count>.<short-sha>` for
`CFBundleVersion`. No manual version-bumping required for normal commits.

## Test

```sh
./run-tests.sh   # xcodebuild test → TimelinerTests
```

Test suite (~26 tests) covers:
- GRDB v1 + v2 migration round-trip, cascade-delete behavior, and
  polymorphic-attachments shape (including BLOB column type)
- Codable round-trips for Case / Event / Importance / HexColor
- Cross-case search ranking determinism
- HTML export self-containment + XSS escaping
- BackupService debounce + retention trim + auto-mkdir + sort order
- `SampleDataService` JSON parsing for both shape variants
  (Madeline-style and Harmony/Athena-style), role/importance/date
  mapping coverage, case-status heuristic

## Default output locations

| Kind | Location |
|---|---|
| Database | `~/Library/Application Support/Timeliner/timeliner.sqlite` |
| Settings | `~/Library/Application Support/Timeliner/settings.json` |
| Attachments | inside `timeliner.sqlite` as BLOBs (carried by the database backup) |
| Backups | `~/Downloads/Timeliner backup/Timeliner-yyyy-MM-dd-HHmmss.zip` |
| HTML / PDF exports | `~/Downloads/Timeliner/<CaseTitle>-<timestamp>.{html,pdf}` |

All output paths are user-overridable in Settings, but the override is
persisted so it sticks across launches. Backup and export directories are
created on demand if they don't exist.

## Roadmap

**Phase 1 (MVP)** — shipped at commit `20017c6`.
**Phase 2** — shipped on top of MVP: attachments (polymorphic, BLOB,
backup-carried), horizontal pan/zoom timeline, cross-case combined
timeline, custom theme builder with live preview, per-slot font
customization, PDF export, anniversary reminders.
**Phase 3** — iOS companion via CloudKit sync, multi-case index export,
case templates, full block-level markdown rendering.
