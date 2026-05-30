# Installing PurpleDiary

## Prerequisites

- **macOS 14.0 (Sonoma) or later.**
- **Full Xcode** (not just Command Line Tools) — `xcode-select -p` should point
  at `/Applications/Xcode.app/Contents/Developer`. Set it with:
  ```sh
  sudo xcode-select -s /Applications/Xcode.app
  ```
- **XcodeGen** on PATH:
  ```sh
  brew install xcodegen
  ```
- *(Optional)* an Apple **Developer ID Application** signing identity in your
  login Keychain — `build-app.sh` auto-detects it. Without it the app is
  ad-hoc signed (fine for local use).

## Build & install

```sh
cd PurpleDiary
./build-app.sh
```

This regenerates the Xcode project, builds Release, installs to
`/Applications/PurpleDiary.app`, and launches it. Opt-out flags:

```sh
./build-app.sh --no-open       # install without focus-stealing relaunch
./build-app.sh --no-install    # build only (leaves ./PurpleDiary.app)
BUILD_ONLY=1 ./build-app.sh    # same, via env
```

Re-install a previously built bundle without rebuilding:

```sh
./install.sh
./install.sh --no-open
```

## Run the tests

```sh
./run-tests.sh
```

## Where your data lives

- Journal database: `~/Library/Application Support/PurpleDiary/diary.sqlite`
- Settings: `~/Library/Application Support/PurpleDiary/settings.json`
- Automatic backups: `~/Downloads/PurpleDiary backup/`

A backup runs automatically every launch (unless one ran in the last five
minutes). You can run one on demand and restore from Settings → Backup.
