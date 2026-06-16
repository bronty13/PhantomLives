# PurplePeek

A macOS media-triage app. Browse or drag a folder, and PurplePeek recursively discovers
every photo, video, and audio file inside it so you can visually triage them — keep/skip,
favorite, title, caption, keywords, albums — before importing the keepers into your Photos
library. Decisions persist in a local database keyed by file path, so you can revisit a
folder and only re-review the items you haven't decided yet.

Two views:

- **Browse** — a Finder-like folder tree + thumbnail grid with a per-item detail panel.
- **Preview** — a one-by-one walkthrough of undecided items in a large viewer, with full
  EXIF metadata.

When you're ready, an **Import to Photos** wizard brings the keepers in (with verification
and a report), and **delete** tools clean up imported / skipped files from disk.

## "Mirror Photos" design principle

PurplePeek only offers decisions that macOS Photos can actually hold: **title, caption,
keywords, favorite, album**. Photos has no star rating, so PurplePeek has none either.
Title/caption/keywords are embedded into a staged copy of each file (via `exiftool`) so
Photos ingests them on import; favorite and album are applied through PhotoKit. **Audio is
never imported to Photos** (Photos holds images + videos only) — kept audio is copied to a
configurable export folder instead.

## Build

```sh
./build-app.sh          # build + install to /Applications + relaunch
./build-app.sh --no-install   # build only
```

Requires macOS 14+. Optional runtime tool: `exiftool` (`brew install exiftool`) to embed
title/caption/keywords into Photos imports — without it, originals import with no embedded
metadata.

## Tests

```sh
./run-tests.sh    # XCTest (21 tests) — uses full Xcode's XCTest via DEVELOPER_DIR
```

Covers migrations + decision-preserving re-scan upsert + cascade delete, media discovery
classification, backup retention, and the audio/delete/staging services.

## Default output location

- Kept audio: `~/Downloads/PurplePeek/Kept Audio/`
- Auto-backups: `~/Downloads/PurplePeek backup/`

Both are configurable in Settings.

## Status

Feature-complete: scan → browse/preview → decide → import to Photos (with staged metadata) /
keep-export audio → delete → manage in Settings. See `CHANGELOG.md` for per-phase detail.
