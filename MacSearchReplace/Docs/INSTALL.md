# Installing MacSearchReplace

Personal-use, locally built. Not on the App Store, not notarized — you build it yourself and ad-hoc sign it.

## Requirements

| Component                     | Minimum    |
|-------------------------------|------------|
| macOS                         | 14.0       |
| Apple Silicon or Intel        | either     |
| Swift toolchain               | 5.9 / 6.x  |
| Xcode Command Line Tools      | latest     |
| Disk space                    | ~250 MB (build artefacts) |

Xcode itself is **not** required for the CLI or `.app` bundle. Only `swift-testing` integration tests need a full Xcode install.

## One-shot install

```bash
git clone https://github.com/bronty13/PhantomLives.git
cd PhantomLives/MacSearchReplace
./Scripts/fetch-ripgrep.sh         # downloads & vendors a universal ripgrep
./Scripts/build-app.sh             # builds + ad-hoc signs MacSearchReplace.app
open build/MacSearchReplace.app
```

The first launch may be blocked by Gatekeeper (since the app is ad-hoc signed). To clear the quarantine bit on a self-built copy:

```bash
xattr -dr com.apple.quarantine build/MacSearchReplace.app
```

Then drag `MacSearchReplace.app` into `/Applications` (optional).

## Installing the `snr` CLI

```bash
swift build -c release --product snr
sudo install -m 0755 .build/release/snr /usr/local/bin/snr
snr --help
```

Or skip `sudo` and put it on your `PATH`:

```bash
mkdir -p ~/bin
cp .build/release/snr ~/bin/snr
export PATH="$HOME/bin:$PATH"   # add to your shell rc
```

## Running the smoke tests

After a clean build:

```bash
./Tests/smoke.sh
```

Expect ~16 tests, all passing. The script creates fixtures in `/tmp` and cleans up after itself.

## Where data is stored

| Data                      | Location |
|---------------------------|----------|
| App preferences           | `~/Library/Preferences/com.robertolen.MacSearchReplace.plist` |
| Favorites (saved searches)| `~/Library/Application Support/MacSearchReplace/favorites.json` |
| Backup sessions           | `~/Library/Application Support/MacSearchReplace/Backups/<timestamp>/` |

Backups are APFS clonefile snapshots, so they're effectively free in disk space until the original file is modified.

## Updating

```bash
cd PhantomLives
git pull
./Scripts/build-app.sh
```

## Uninstalling

```bash
rm -rf /Applications/MacSearchReplace.app build/MacSearchReplace.app
rm -rf "$HOME/Library/Application Support/MacSearchReplace"
defaults delete com.robertolen.MacSearchReplace 2>/dev/null
sudo rm -f /usr/local/bin/snr
```
