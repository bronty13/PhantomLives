# Installing Timeliner

Timeliner ships as a `.app` bundle built locally from this directory.

## Prerequisites

- macOS 14.0 or later
- **Full Xcode** (the build uses `xcodebuild` and SwiftPM via XcodeGen)
- `xcodegen` on `PATH` — install via Homebrew: `brew install xcodegen`

If `xcode-select -p` points at the Command Line Tools but
`/Applications/Xcode.app` exists, the build script auto-overrides
`DEVELOPER_DIR` to use Xcode for that run only. No need to
`xcode-select --switch` permanently.

## Build

```sh
cd ~/Documents/GitHub/PhantomLives/Timeliner
./build-app.sh
```

Output: `./Timeliner.app` in this directory.

To install:

```sh
mv ./Timeliner.app /Applications/
open /Applications/Timeliner.app
```

## First launch

The first launch:
- Creates `~/Library/Application Support/Timeliner/` and an empty SQLite
  database at `timeliner.sqlite`.
- Seeds the tags table with six defaults (evidence, witness, suspect,
  court, scene, media).
- Tries to run an auto-backup — silently skipped if the database is brand
  new (the zip is essentially empty), but the
  `~/Downloads/Timeliner backup/` directory is created.

Settings live alongside the database at `settings.json` and are written
in human-readable JSON.

## Code signing

`build-app.sh` looks for a "Developer ID Application" certificate via
`security find-identity` and signs with it (with hardened runtime + Apple
timestamp) if one is present. Otherwise it uses ad-hoc signing — fine for
local use, won't pass Gatekeeper on a fresh Mac without a Developer ID.

## Updating

Re-run `./build-app.sh`. The version number is auto-derived from git, so
each commit produces a new `CFBundleShortVersionString` and
`CFBundleVersion`. No manual version-bumping required.
