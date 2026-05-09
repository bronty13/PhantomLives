# PurpleDedup — Install

## From source

```bash
cd ~/Documents/GitHub/PhantomLives/PurpleDedup
./build-app.sh
```

Produces `PurpleDedup.app` in the project directory. Move it where you like:

```bash
mv PurpleDedup.app /Applications/
```

If `~/Applications` is preferred for personal use, that works too.

## CLI on `$PATH`

The build embeds the `pdedup` CLI binary inside the app bundle. To use it from a
shell:

```bash
mkdir -p ~/bin
ln -sf "/Applications/PurpleDedup.app/Contents/MacOS/pdedup" ~/bin/pdedup
# Make sure ~/bin is on PATH; bash/zsh-typical .zshrc / .bashrc:
#   export PATH="$HOME/bin:$PATH"
```

Verify:

```bash
pdedup version
pdedup scan ~/Pictures --photos-only -q -o ~/Downloads/PurpleDedup/report.json
```

> **Why `pdedup` and not `purplededup`?** macOS's default APFS volume is
> case-insensitive, so the SwiftPM products `PurpleDedup` (the GUI) and
> `purplededup` (the original CLI name) would land at the same bin-path file
> and overwrite each other. The CLI is named `pdedup` to avoid the collision.

## Requirements

- macOS 14 Sonoma or later (Apple Silicon recommended)
- Xcode 15+ command-line tools or full Xcode for building
- No third-party dependencies pre-installed; SwiftPM resolves GRDB and
  swift-argument-parser on first build

## Uninstall

```bash
rm -rf /Applications/PurpleDedup.app
rm -f  ~/bin/pdedup
rm -rf ~/Library/Application\ Support/PurpleDedup
# Backups (only if you want to delete them):
rm -rf ~/Downloads/PurpleDedup\ backup
# Reports written by the CLI:
rm -rf ~/Downloads/PurpleDedup
```

## Code signing notes

`build-app.sh` auto-detects a Developer ID Application certificate in your keychain
and uses it; otherwise it ad-hoc signs with `codesign --sign -`. Ad-hoc signing is
fine for personal / family distribution — first-launch will require the
right-click → Open dance once per Mac. For a real Developer ID build, set
`CODESIGN_IDENTITY="Developer ID Application: …"` before running the script.

## Notarization

To distribute the .app to family / friends without each of them seeing the
"developer cannot be verified" Gatekeeper warning, get the bundle notarized by
Apple. One-time setup:

1. **Create an app-specific password** at
   <https://appleid.apple.com/account/manage> → *App-Specific Passwords*.
2. **Store it in the keychain** as a notarytool credential profile:
   ```bash
   xcrun notarytool store-credentials "PurpleDedup-Notary" \
       --apple-id you@example.com \
       --team-id SRKV8T38CD \
       --password <the app-specific password>
   ```
   The Team ID for the current Developer ID is in
   `codesign -dv PurpleDedup.app | grep TeamIdentifier`.
3. **Build with notarization enabled**:
   ```bash
   NOTARIZE_PROFILE=PurpleDedup-Notary ./build-app.sh
   ```
   The script zips the bundle, submits it to Apple's notary service, waits
   for the verdict (typically 1–5 minutes), then runs `xcrun stapler staple`
   so the ticket lives inside the bundle. After that, the .app launches
   without warnings on any Mac, even offline.

Skipping the env var leaves the build at the same plain-Developer-ID-signed
state — fine for personal use, just shows the standard first-launch alert
on a fresh Mac.
