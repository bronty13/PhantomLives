# PurplePeek

A macOS media-triage app. Browse or drag a folder, and PurplePeek recursively discovers
every photo, video, and audio file inside it so you can visually triage them — keep/skip,
favorite, title, caption, keywords, albums — before importing the keepers into your Photos
library. Decisions persist in a local database keyed by file path, so you can revisit a
folder and only re-review the items you haven't decided yet.

**Exact duplicates are decided once.** After each scan PurplePeek finds byte-for-byte identical
files (content hash, with a size pre-filter so it's fast), shows each set as one item with a
**×N** badge, applies your keep/skip to every copy, and imports only one copy of a kept set.
Toggle it off in Settings → General.

To keep the view in step with disk, **Refresh** (toolbar button / **⌘R**, or right-click any
folder in the sidebar → **Refresh**) re-scans the selected folder — picking up newly added files
and flagging any that were removed or moved as **missing** (an orange grid badge; they reappear
normally if the file comes back), all without disturbing your decisions. Turn on **Settings →
General → "Watch folder for changes"** to have PurplePeek auto-refresh whenever the folder
changes on disk.

Two views:

- **Browse** — a Finder-like folder tree + thumbnail grid with a per-item detail panel. A
  **Show** menu filters the grid by decision (All / Undecided / Decided / Kept / Skipped), so
  you can revisit choices, not just triage new items. Press **Space** on a selected item to
  **peek** it full-size in Quick Look (press Space again to close); clicking through items
  while the peek is open updates it live.
- **Preview** — a one-by-one walkthrough in a large viewer with full EXIF metadata. Keyboard-
  driven: **Y** keep · **N** skip · **F** favorite · **H** hidden · **←/→** navigate ·
  **Space** Quick Look. A **Review** menu picks which queue you step through (Undecided by
  default). All keys are suspended while a title/caption field has focus, so you can type
  freely.

When you're ready, an **Import to Photos** wizard brings the keepers in (with verification
and a report), and **delete** tools clean up imported / skipped files from disk. Set an item's
title/caption/keywords **before** importing — they're embedded into the file so Photos ingests
them on import (there's no way to push metadata to an item already in your library).

## "Mirror Photos" design principle

PurplePeek only offers decisions that macOS Photos can actually hold: **title, caption,
keywords, favorite, album, hidden**. Photos has no star rating, so PurplePeek has none either.
Favorite, hidden, and album are applied through PhotoKit; title/caption/keywords reach Photos
by `exiftool`-embedding them into a staged copy before import — XMP/IPTC for photos, the
QuickTime `Keys:` group for videos — which Photos ingests natively (no "control Photos"
automation prompt; see *Requirements & permissions* below). **Audio is never imported to
Photos** (Photos holds images + videos only) — kept audio is copied to a configurable export
folder instead.

## Build

```sh
./build-app.sh          # build + install to /Applications + relaunch
./build-app.sh --no-install   # build only
```

## Requirements & permissions

- **macOS 14+.**
- **Photos access** — granted on first import (Add-to-library + read/write). This is the
  **only** permission prompt PurplePeek shows; there's no "control Photos" automation prompt.
- **`exiftool`** *(optional — `brew install exiftool`)* — embeds title/caption/keywords into a
  staged copy of each **photo and video** before import. Without it, items import with no
  embedded metadata (favorite/hidden/album still apply via PhotoKit).
- **`osxphotos`** *(optional — `pipx install osxphotos`)* — powers Keyword Manager →
  **Import from Photos**, which seeds the local keyword vocabulary from your library (PhotoKit
  can't read keywords). The button is disabled with guidance when it isn't installed.

### Why embed metadata before import?

PhotoKit can only write four asset properties — `creationDate`, `location`, `isFavorite`,
`isHidden` — and offers no way to set title/caption/keywords. So **favorite + hidden + album**
go straight through PhotoKit, and **title/caption/keywords** are embedded into the file with
`exiftool` *before* import (XMP/IPTC for photos, the QuickTime `Keys:` group for videos), which
Photos reads on ingest. This is the same embed-then-import approach osxphotos and other Photos
tools use — and it's why PurplePeek needs no Apple Events / "control Photos" automation grant.
(Earlier versions drove Photos via AppleScript for videos; that caused a recurring TCC prompt
and was removed — see `docs/tcc-prompt-research-spike.md`.)

## Tests

```sh
./run-tests.sh    # XCTest (40 tests) — uses full Xcode's XCTest via DEVELOPER_DIR
```

Covers migrations (incl. the `v1_initial` immutability ledger + the `v2_add_is_hidden`
round-trip), decision-preserving re-scan upsert + cascade delete, the re-scan
missing-file reconciliation (mark-missing / reappear-clears / deleted-stays-deleted), the
sidebar section columns + delete-fallback + reorder, the duplicate hash pre-filter +
re-hash-on-change + content hashing, media-discovery classification + top-level exclude, the
decision-filter lens, backup retention, and the audio / delete / staging services.

## Default output location

- Kept audio: `~/Downloads/PurplePeek/Kept Audio/`
- Auto-backups: `~/Downloads/PurplePeek backup/`

Both are configurable in Settings.

## Documentation

- **`USER_MANUAL.md`** — how to use PurplePeek, task by task (also the place to point a new user).
- **`DESIGN.md`** — the *why* behind the non-obvious decisions (Mirror Photos, the three
  metadata paths, missing-vs-deleted, the cached-derived performance layer).
- **`HANDOFF.md`** — architecture snapshot + module map; read before non-trivial changes.
- **`CHANGELOG.md`** — what changed when.

## Status

Feature-complete: scan → browse/preview → decide → import to Photos (with staged metadata) /
keep-export audio → delete → manage in Settings. See `CHANGELOG.md` for per-phase detail.
