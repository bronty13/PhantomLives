# PurpleDedup

A native macOS photo & video deduplication tool. SwiftPM, Apple Silicon optimized, no
subscription, no nags. For personal / family use — distributed by direct download, not
the App Store.

## Status

**Phase 3: Video fingerprinting.** Three pipeline stages now: byte-exact (Phase 1),
visually-similar photos (Phase 2), and visually-similar videos (Phase 3). Videos are
sampled at 1 frame/second via AVFoundation, each frame pHashed, sequences aligned and
compared by mean Hamming distance. Same JSON report shape, with `similar_video`
clusters joining `exact` and `similar_photo`.

Subsequent phases are scoped in `~/Downloads/Dedupr-Requirements.md` (the design doc
this app implements). Roadmap:

| Phase | Scope | Status |
|---|---|---|
| 1 | Foundation: exact dupes, CLI, minimal app, GRDB cache | ✅ shipped 0.1.0 |
| 2 | Perceptual photo matching (pHash + dHash, BK-tree) | ✅ shipped 0.2.0 |
| 3 | Video fingerprinting (AVFoundation keyframe pHash) | ✅ shipped 0.3.0 |
| 4 | Cached engine, threshold-without-rescan, launch-time backup, Settings pane | ✅ shipped 0.4.0 |
| 4.5 | Three-pane comparison UI, EXIF/codec metadata, diff highlighting, QuickLook | ✅ shipped 0.7.0 |
| 5 | Smart-select rules + cleanup workflow + operation log undo | ✅ shipped 0.8.0 |
| 6 | Apple Photos library support (read-only walk + auto-lock) | ✅ shipped 0.9.0 |
| 6.5 | PhotoKit-based "Marked for Deletion" album round-trip | ✅ shipped 0.14.0 |
| 7 | Polish, perf, sessions, code signing, notarization | planned |

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

Drop folders into the window or use **Add Folder…**, then click **Scan**. Phase 1 lists
exact-duplicate clusters and the bytes you'd reclaim. Move-to-trash UX lands in Phase 5.

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
