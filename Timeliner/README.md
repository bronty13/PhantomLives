# Timeliner

A native macOS SwiftUI app for organizing, visualizing, and sharing case
timelines. Built for true-crime enthusiasts (or anyone who wants to track a
chronologically structured story) — fully offline, single-user, with a
local SQLite database and a polished customizable UI.

## At a glance

- **Cases** with status (active / cold / closed) and pinning
- **Events** per case with date, markdown description, source URL, and a
  four-level importance indicator
- **Tags** with custom colors and per-event tagging
- **People / persons of interest** with role-based chips (suspect, victim,
  witness, attorney, detective, other) and per-event linking
- **Vertical chronological timeline** grouped by year and month with
  date/tag/importance filters
- **Cross-case search** ranked by title-prefix > title-substring >
  body match
- **Standalone HTML export** — one self-contained file per case (CSS + JS
  inlined, no external dependencies) dropped at `~/Downloads/Timeliner/`
- **Auto-backup at every launch** — zips the database and settings into
  `~/Downloads/Timeliner backup/` with retention trimming. Verify and
  restore from the Settings → Backup tab.
- **Themes** — six built-in themes (Default, Midnight, Ocean, Forest,
  Sunset, Rose). Custom theme builder lands in Phase 2.

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

Test suite covers:
- GRDB v1 migration round-trip + cascade-delete behavior
- Codable round-trips for Case / Event / Importance / HexColor
- Cross-case search ranking determinism
- HTML export self-containment + XSS escaping
- BackupService retention trim + auto-mkdir + sort order

## Default output locations

| Kind | Location |
|---|---|
| Database | `~/Library/Application Support/Timeliner/timeliner.sqlite` |
| Settings | `~/Library/Application Support/Timeliner/settings.json` |
| Attachments (Phase 2) | `~/Library/Application Support/Timeliner/attachments/<sha256>` |
| Backups | `~/Downloads/Timeliner backup/Timeliner-yyyy-MM-dd-HHmmss.zip` |
| HTML exports | `~/Downloads/Timeliner/<CaseTitle>-<timestamp>.html` |

All output paths are user-overridable in Settings, but the override is
persisted so it sticks across launches. Backup and export directories are
created on demand if they don't exist.

## Roadmap

**Phase 1 (MVP)** — shipped.
**Phase 2** — attachments (images/PDFs, content-addressed), horizontal
pan/zoom timeline (Canvas + GeometryReader), theme builder with live
preview, font customization (per-element `FontStyle` slots), PDF export,
date-anniversary reminders.
**Phase 3** — iOS companion via CloudKit sync, multi-case index export,
case templates.
