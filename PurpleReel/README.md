# PurpleReel

Media management for Final Cut Pro. A Kyno-style browser, logger, and
delivery tool — FCP-only, AI-augmented (Whisper transcripts, perceptual
selects, LLM auto-descriptions), and integrated with the rest of the
PhantomLives stack.

## Status

Phase 1 skeleton — Finder-rooted scanner, SQLite (GRDB) catalog, asset
table view with codec / resolution / fps / duration / size, auto-backup
on launch. No player, transcoder, FCPXML, SFTP, or AI features yet —
see `~/.claude/plans/zany-greeting-willow.md` for the full plan.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16
- `xcodegen` (`brew install xcodegen`)

## Build & install

```sh
./build-app.sh && ./install.sh
```

`build-app.sh` regenerates the AppIcon from `Scripts/generate-icon.swift`,
runs xcodegen, compiles Release, and signs (Developer ID if available,
ad-hoc otherwise). `install.sh` quits any running copy and ditto-copies
into `/Applications/` so TCC permissions stick across rebuilds.

## Where things land

- Catalog DB: `~/Library/Application Support/PurpleReel/purplereel.sqlite`
- Auto-backups: `~/Downloads/PurpleReel backup/PurpleReel-YYYY-MM-DD-HHmmss.zip`
- User output (transcodes, exports — once implemented): `~/Downloads/PurpleReel/`

## Layout

```
Scripts/generate-icon.swift     # programmatic film-reel app icon
Sources/PurpleReel/
  App/                          # @main, AppState, Info.plist, entitlements
  Models/                       # Asset, etc.
  Services/                     # DatabaseService, MediaScanner, BackupService
  Views/                        # ContentView, BrowserView, SettingsView
  Resources/Assets.xcassets/    # AppIcon + AccentColor
Tests/PurpleReelTests/
project.yml                     # XcodeGen
build-app.sh / install.sh
```
