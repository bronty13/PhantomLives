# PurpleLife — Install

## Prerequisites

- macOS 14 or later.
- **Full Xcode** (not just Command Line Tools) — `xcodebuild` won't run under CLT.
- `xcodegen` — `brew install xcodegen`.
- Optional: an Apple Developer account configured in Xcode for signing (without one, `build-app.sh` falls back to ad-hoc signing — fine for personal local use).

## Build & install

```sh
cd PurpleLife
./build-app.sh
mv PurpleLife.app /Applications/    # or anywhere; ~/Applications works too
```

The first launch creates `~/Library/Application Support/PurpleLife/` and writes a baseline backup to `~/Downloads/PurpleLife backup/`.

## Run the tests

```sh
./run-tests.sh
```

Phase 1 ships 9 tests (4 required backup tests + 1 Phase 1 acceptance round-trip + 3 ObjectEngine smoke tests). All must pass before any Phase 1 PR merges, per the standing release-hygiene rule in `CLAUDE.md`.

## CloudKit spike (separate target)

```sh
cd Spike/CloudKit
./build-spike.sh
open CloudKitSpike.app
```

The spike requires an iCloud-signed-in Mac and a CloudKit container provisioned at <https://developer.apple.com/account>. Full procedure in `Spike/CloudKit/SPIKE.md`.

## Uninstall

```sh
rm -rf /Applications/PurpleLife.app
rm -rf ~/Library/Application\ Support/PurpleLife
# Optional — keeps your backups around in case you reinstall:
# rm -rf ~/Downloads/PurpleLife\ backup
```
