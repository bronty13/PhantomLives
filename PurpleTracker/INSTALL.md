# INSTALL — PurpleTracker

## Requirements

- macOS 14 (Sonoma) or newer.
- Apple Silicon or Intel.
- For building from source: Xcode 16, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`).

## Install the prebuilt app

1. Copy `PurpleTracker.app` to `/Applications`.
2. Right-click → **Open** the first time (because the build is ad-hoc signed).
3. The app creates its database & runs an automatic backup on first launch.

Storage locations created on first launch:

| Purpose                | Path                                                                 |
|------------------------|----------------------------------------------------------------------|
| Database               | `~/Library/Application Support/PurpleTracker/purpletracker.sqlite`   |
| Settings               | `~/Library/Application Support/PurpleTracker/settings.json`          |
| Auto-backups (default) | `~/Downloads/PurpleTracker backup/`                                  |
| Exports (default)      | `~/Downloads/PurpleTracker/`                                         |

All paths above are user-overridable from **Settings**.

## Build from source

```sh
cd ~/Documents/GitHub/PhantomLives/PurpleTracker
xcodegen generate          # produces PurpleTracker.xcodeproj
./run-tests.sh             # 22 tests, ~1 s
./build-app.sh             # produces ./PurpleTracker.app
open ./PurpleTracker.app   # launches the built app
```

`build-app.sh` stamps the bundle version from `git rev-list --count HEAD` and
the short SHA, then ad-hoc signs (or uses Developer ID if one is in the
keychain).

GRDB is vendored under `Vendor/GRDB` (a shallow clone of `v6.29.3`) instead of
being pulled from SwiftPM, because the local Xcode toolchain forces
`safe.bareRepository=explicit` on its child `git` invocations and refuses to
read SPM's bare repo cache. The vendored copy makes the build hermetic.

## Uninstall

```sh
rm -rf /Applications/PurpleTracker.app
rm -rf ~/Library/Application\ Support/PurpleTracker
# Optional — only if you no longer want your backup history:
rm -rf ~/Downloads/PurpleTracker\ backup
rm -rf ~/Downloads/PurpleTracker
```
