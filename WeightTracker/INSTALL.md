# WeightTracker — Installation

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ (to build from source)
- XcodeGen: `brew install xcodegen`

## Build from Source

```bash
cd ~/Documents/GitHub/PhantomLives/WeightTracker

# 1. Generate the Xcode project
xcodegen generate

# 2. Open in Xcode and build (⌘R)
open WeightTracker.xcodeproj

# — or — build a release .app bundle from the command line:
./build-app.sh
```

The built app appears as `WeightTracker.app` in the project directory.

> **After adding new source files**, run `xcodegen generate` again to include them in the project before building.

## First Launch

WeightTracker creates its database and settings automatically on first launch:

```
~/Library/Application Support/WeightTracker/
    weighttracker.sqlite    # all your weight entries
    settings.json           # preferences
```

Exports and backups default to `~/Downloads/WeightTracker/` (created on demand).

## Permissions

No additional permissions beyond what the sandbox grants:

| Permission | Purpose |
|-----------|---------|
| Downloads folder access | Automatic backups and default export location |
| User-selected files (read-write) | Importing photos; exporting to custom paths |
| Print | PDF and print report generation |

## Uninstall

1. Delete `WeightTracker.app`
2. Remove data (optional): `rm -rf ~/Library/Application\ Support/WeightTracker`
3. Remove exports/backups (optional): `rm -rf ~/Downloads/WeightTracker`
