# PurpleDiary

A native macOS SwiftUI journaling app inspired by [Diarium](https://diariumapp.com).
Local-first, private, no account — your journal lives in a single SQLite
database on your Mac. See [SCOPING.md](SCOPING.md) for the full design brief and
phased roadmap.

> **Status:** Phase-1 scaffold. The core journal (write, browse, search, tag,
> mood, backup) is in place. Auto-assembled days (Photos/Calendar/WeatherKit),
> tracker tags, map view, encryption-at-rest, and sync are scoped for later
> phases — see SCOPING.md.

## At a glance (Phase 1)

- **Entries** — Markdown body, optional title, editable date/time, multiple
  entries per day. Live word count.
- **Mood** — 0–5 star rating per entry.
- **Tags** — named, colored, toggleable per entry; six seeded on first launch.
- **People** — a global list of recurring people you can link to entries.
- **Timeline** — entries grouped by month, newest first, with an inline editor.
- **Calendar** — month grid; days with entries are dotted; click to jump or
  create.
- **Search** — ranked across title / body / tags / people.
- **Auto-backup at every launch** — zips the support directory to
  `~/Downloads/PurpleDiary backup/` with 14-day retention; verify and restore
  from Settings → Backup. (PhantomLives convention.)
- **App-lock toggles** — UI present; lock screen + Keychain wiring is the next
  milestone.

## Build

```sh
./build-app.sh          # build + install to /Applications + relaunch
./build-app.sh --no-open
./build-app.sh --no-install   # build only
```

The build script regenerates `PurpleDiary.xcodeproj` from `project.yml` via
`xcodegen`, generates the app icon programmatically
(`Scripts/generate-icon.swift`), builds Release in `/tmp` (avoids iCloud xattr
issues), signs with your Developer ID if present (ad-hoc otherwise), then
hands off to `install.sh`.

Version is auto-derived from git: `1.0.<commit-count>` for
`CFBundleShortVersionString`, `<count>.<short-sha>` for `CFBundleVersion`. No
manual version bumping.

**Requires full Xcode** (not just Command Line Tools) and `xcodegen` on PATH.

## Test

```sh
./run-tests.sh          # xcodebuild test → PurpleDiaryTests
```

Test suite covers GRDB migrations + cascade behavior, model Codable/word-count,
search ranking, and BackupService debounce/retention/verify.

## Project layout

```
PurpleDiary/
├── Sources/PurpleDiary/
│   ├── App/          # PurpleDiaryApp, AppState, AppDelegate, AppMenuCommands, Version, Info.plist
│   ├── Models/       # Entry, Mood, Tag, Person, AppSettings (GRDB records)
│   ├── Services/     # DatabaseService, BackupService, SearchService, SampleDataService, WindowStateGuard
│   └── Views/        # ContentView (HStack sidebar), Timeline, EntryEditor, Calendar, Search, People, Tags, Settings/, Shared/
├── Tests/PurpleDiaryTests/
├── Scripts/generate-icon.swift
├── project.yml · build-app.sh · install.sh · run-tests.sh
```

## Default output locations

| Kind | Location |
|---|---|
| Database | `~/Library/Application Support/PurpleDiary/diary.sqlite` |
| Settings | `~/Library/Application Support/PurpleDiary/settings.json` |
| Backups | `~/Downloads/PurpleDiary backup/PurpleDiary-yyyy-MM-dd-HHmmss.zip` |
| Exports (Phase 2) | `~/Downloads/PurpleDiary/` |

All output paths are user-overridable in Settings; the override persists.
