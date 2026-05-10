# PurpleDedup

A native macOS photo & video deduplication tool. SwiftPM, Apple Silicon optimized, no
subscription, no nags. For personal / family use — distributed by direct download, not
the App Store.

## Status

**0.18.4 — Photos library lookup mode + filters + Tahoe-tuned UI.** All seven
phases of the requirements doc plus a long list of user-driven additions are
shipped. See `CHANGELOG.md` for the per-version detail.

What works today:

- **Three pipeline stages.** Byte-exact (SHA-1, parallel), visually-similar
  photos (pHash + dHash, BK-tree, capped at 6 concurrent because the
  hardware HEVC decoder serializes), visually-similar videos (1-fps frames
  capped at 12 per video, mean Hamming over aligned sequences).
- **Apple Photos library integration.** Add your `.photoslibrary` as a
  scan source — files marked DELETE queue in a "Marked for Deletion in
  PurpleDedup" album that you finalise inside Photos.app. Per-library
  filter (albums / subtypes / favorites / **only hidden**). Lookup-only
  mode treats the library as a read-only reference index and badges
  folder duplicates that already live in Photos.
- **Hidden-album dedup.** Bypasses the macOS 14+ Locked Hidden Album
  privacy gate by reading `Photos.sqlite` directly; works even when
  PhotoKit refuses to surface `isHidden`.
- **Smart-select rule chain.** Configurable folder-priority + 9 other
  rules (highest-resolution, most-metadata, newest-capture, etc.) drive
  per-cluster KEEP/DELETE recommendations. Manual overrides survive
  re-running the rules.
- **Per-thumbnail badges.** KEEP / DELETE chip, "In Photos" capsule, and
  orange "Hidden" tag let you size up a cluster at a glance.
- **Cancel + force-quit** mid-scan. ⌘. unwinds in <1 second; if a
  non-cancellable phase is stuck, the toolbar offers a brutal `exit(0)`
  after 4 seconds of waiting.
- **GRDB-backed cache.** First run on a 5 600-file folder: ~19 s. Second
  run: <1 s.
- **Save plan as JSON** (FR-5.9 dry-run) — every cluster + decision out
  to a file without touching the filesystem.
- **GUI + CLI** share the same engine (`pdedup scan ~/Pictures …`).

## Build

```bash
./build-app.sh         # produces PurpleDedup.app (signed if a Developer ID cert exists)
./run-tests.sh         # runs the Core test suite
```

`build-app.sh` derives `CFBundleShortVersionString` from `git rev-list --count HEAD` and
embeds the short SHA in `CFBundleVersion`. Override either via `SHORT_VERSION=…
BUILD_NUMBER=… ./build-app.sh`.

## Run

### GUI

```bash
open PurpleDedup.app
```

Drop folders into the sidebar, use **Add Folder…**, or **Add Photos library…**.
Click **Scan**. Cluster list populates as the engine works; click any cluster to
open the comparison pane (thumbnail grid + metadata table with diff highlighting).
KEEP / DELETE badges show the rule-chain recommendation; right-click a thumbnail
to override or to trash a single file. **Trash** in the toolbar opens the
preflight modal with the full delete plan.

Per-Photos-library controls live in the source row: **🔍 lookup-only**,
**☰ filter**, **− remove**. Filter is an inline editor that takes over the
sidebar — albums multi-select, media subtypes, Favorites only / Include
hidden / **Only hidden**.

Cancel a running scan with **⌘.** or the red Cancel button in the toolbar.
After 4 seconds the button morphs into a Force-Quit fallback for any
non-cancellable phase that's stuck.

### CLI

```bash
PurpleDedup.app/Contents/MacOS/pdedup scan ~/Pictures
PurpleDedup.app/Contents/MacOS/pdedup scan ~/Pictures -o ~/Downloads/PurpleDedup/report.json
PurpleDedup.app/Contents/MacOS/pdedup scan ~/Pictures --photos-only --quiet
PurpleDedup.app/Contents/MacOS/pdedup scan ~/Pictures --similar-threshold 12   # looser
PurpleDedup.app/Contents/MacOS/pdedup scan ~/Pictures --no-similar             # exact only
PurpleDedup.app/Contents/MacOS/pdedup version
```

The CLI emits a JSON report on stdout (or to `-o <path>`) and human-readable progress on
stderr. Exit code 0 on success regardless of whether duplicates were found.

To install the CLI on `$PATH`:

```bash
mkdir -p ~/bin
ln -sf "$PWD/PurpleDedup.app/Contents/MacOS/pdedup" ~/bin/pdedup
```

## Filesystem layout

| Purpose | Path |
|---|---|
| User-visible reports (default) | `~/Downloads/PurpleDedup/` |
| Backup archives | `~/Downloads/PurpleDedup backup/` |
| SQLite cache + settings | `~/Library/Application Support/PurpleDedup/` |

The first two are PhantomLives conventions (see `../CLAUDE.md`); the third is sandbox-
neutral and matches macOS `applicationSupportDirectory`.

## Privacy

PurpleDedup is fully local. No network calls. No analytics. No accounts.

The only filesystem writes outside `~/Library/Application Support/PurpleDedup/` are
the reports you ask for explicitly (`-o <path>`) and any move-to-trash operations you
confirm in a future Phase-5 cleanup workflow.

## License

Personal / family use. Not currently licensed for redistribution. Pick a real license
(MIT, BSL, etc.) before sharing the binary outside that circle.
