# Install

## Prerequisites

- macOS 14.0 or later (Apple Silicon recommended)
- Xcode 16 or newer
- `xcodegen` — `brew install xcodegen`
- *Optional:* `ollama` — `brew install ollama` (for description refinement)

If `xcode-select` points at Command Line Tools instead of full Xcode, `build-app.sh` automatically falls back to `/Applications/Xcode.app/Contents/Developer` for that single build.

## Build & install

```bash
cd ~/Documents/GitHub/PhantomLives/MasterClipper
xcodegen generate
./build-app.sh
mv MasterClipper.app /Applications/
open /Applications/MasterClipper.app
```

`build-app.sh` will:

1. Regenerate the Xcode project from `project.yml` (if `xcodegen` is on `PATH`)
2. Render the app icon via `Scripts/generate-icon.swift`
3. Stamp `CFBundleShortVersionString` = `1.0.<git-commit-count>` and `CFBundleVersion` = `<count>.<short-sha>` into `Info.plist`
4. Build a Release configuration into `/tmp/<random>` to avoid iCloud Drive interference
5. Copy the resulting `.app` to the project root and code-sign with **Developer ID** if available, otherwise **ad-hoc**

## First-run housekeeping

On launch the app:

1. Creates `~/Library/Application Support/MasterClipper/` and seeds the database with the four default personas, five sites, and 28 calendar rules
2. Writes `settings.json` with the documented defaults the first time a setting is changed (load is lazy)
3. Runs an auto-backup to `~/Downloads/MasterClipper backup/`
4. Detects Ollama at `/opt/homebrew/bin/ollama` / `/usr/local/bin/ollama` / `/usr/bin/ollama`, starts `ollama serve` if not already running, and pulls the configured model on demand

## Smoke test

```bash
cd ~/Documents/GitHub/PhantomLives/MasterClipper
./run-tests.sh
```

Currently a build smoke test — regenerates the Xcode project and runs `xcodebuild` to verify the project still compiles. Real unit tests aren't wired up yet.

## Uninstall

Quit the app, then:

```bash
rm -rf /Applications/MasterClipper.app                       # the bundle
rm -rf ~/Library/Application\ Support/MasterClipper           # database + settings
rm -rf ~/Downloads/MasterClipper                              # exports
rm -rf ~/Downloads/MasterClipper\ backup                      # backups
```

Customise the `Downloads` paths if you set custom export / backup directories in Settings.
