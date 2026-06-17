# PurplePeek

A macOS media-triage app. Browse or drag a folder, and PurplePeek recursively discovers
every photo, video, and audio file inside it so you can visually triage them — keep/skip,
favorite, title, caption, keywords, albums — before importing the keepers into your Photos
library. Decisions persist in a local database keyed by file path, so you can revisit a
folder and only re-review the items you haven't decided yet.

To keep the view in step with disk, **Refresh** (toolbar button / **⌘R**) re-scans the
selected folder — picking up newly added files and flagging any that were removed or moved as
**missing** (an orange grid badge; they reappear normally if the file comes back), all without
disturbing your decisions. Turn on **Settings → General → "Watch folder for changes"** to have
PurplePeek auto-refresh whenever the folder changes on disk.

Two views:

- **Browse** — a Finder-like folder tree + thumbnail grid with a per-item detail panel. A
  **Show** menu filters the grid by decision (All / Undecided / Decided / Kept / Skipped), so
  you can revisit choices, not just triage new items.
- **Preview** — a one-by-one walkthrough in a large viewer with full EXIF metadata. Keyboard-
  driven: **Y** keep · **N** skip · **F** favorite · **H** hidden · **←/→** navigate ·
  **Space** Quick Look. A **Review** menu picks which queue you step through (Undecided by
  default). All keys are suspended while a title/caption field has focus, so you can type
  freely.

When you're ready, an **Import to Photos** wizard brings the keepers in (with verification
and a report), and **delete** tools clean up imported / skipped files from disk. Already
imported something before setting its metadata? **Photos → Re-apply Metadata to Imported
Items** re-pushes each item's current title/caption/keywords without re-importing.

## "Mirror Photos" design principle

PurplePeek only offers decisions that macOS Photos can actually hold: **title, caption,
keywords, favorite, album, hidden**. Photos has no star rating, so PurplePeek has none either.
Favorite, hidden, and album are applied through PhotoKit; title/caption/keywords reach Photos
via `exiftool` embedding (photos) or AppleScript (videos) — see *Requirements & permissions*
below. **Audio is never imported to Photos** (Photos holds images + videos only) — kept audio
is copied to a configurable export folder instead.

## Build

```sh
./build-app.sh          # build + install to /Applications + relaunch
./build-app.sh --no-install   # build only
```

## Requirements & permissions

- **macOS 14+.**
- **Photos access** — granted on first import (Add-to-library + read/write).
- **Automation consent for Photos** — on the first import (or first *Re-apply Metadata*),
  macOS prompts **"PurplePeek wants to control Photos."** Allow it: this AppleScript path is
  how title/caption/keywords reach **videos** (PhotoKit can't write them, and `exiftool`
  embedding only carries into photos). Deny it and photo metadata still works, but video
  metadata won't.
- **`exiftool`** *(optional — `brew install exiftool`)* — embeds title/caption/keywords into a
  staged copy of each **photo** before import. Without it, photos import with no embedded
  metadata; videos are unaffected (they use the AppleScript path above).
- **`osxphotos`** *(optional — `pipx install osxphotos`)* — powers Keyword Manager →
  **Import from Photos**, which seeds the local keyword vocabulary from your library (PhotoKit
  can't read keywords). The button is disabled with guidance when it isn't installed.

### Why three metadata paths?

PhotoKit can only write four asset properties — `creationDate`, `location`, `isFavorite`,
`isHidden`. So **favorite + hidden + album** go straight through PhotoKit, **photo**
title/caption/keywords are embedded via `exiftool` pre-import, and **video** (or any
photo whose embedding was skipped) title/caption/keywords are set afterward via AppleScript.

## Tests

```sh
./run-tests.sh    # XCTest (29 tests) — uses full Xcode's XCTest via DEVELOPER_DIR
```

Covers migrations (incl. the `v1_initial` immutability ledger + the `v2_add_is_hidden`
round-trip), decision-preserving re-scan upsert + cascade delete, the re-scan
missing-file reconciliation (mark-missing / reappear-clears / deleted-stays-deleted),
media-discovery classification + top-level exclude, the decision-filter lens, backup
retention, and the audio / delete / staging services.

## Default output location

- Kept audio: `~/Downloads/PurplePeek/Kept Audio/`
- Auto-backups: `~/Downloads/PurplePeek backup/`

Both are configurable in Settings.

## Status

Feature-complete: scan → browse/preview → decide → import to Photos (with staged metadata) /
keep-export audio → delete → manage in Settings. See `CHANGELOG.md` for per-phase detail.
