# Releasing PurpleDedup

PurpleDedup auto-updates via [Sparkle 2](https://sparkle-project.org/). This doc covers the **one-time setup** to enable auto-updates and the **per-release flow** to ship a new version to existing users.

## One-time setup

You only do this once per developer machine. After this, every release is just `./Scripts/release.sh`.

### 1. Generate the EdDSA signing keypair

Sparkle 2 verifies updates with EdDSA signatures. The private key lives in your macOS Keychain; the public key is embedded in the shipped Info.plist so installed copies can verify future updates against it.

```bash
# Sparkle's bin/ directory is downloaded by SwiftPM. After the first build:
SPARKLE_BIN="$(find ~/Documents/GitHub/PhantomLives/PurpleDedup/.build/artifacts/sparkle/Sparkle/bin -type d -maxdepth 1 | head -1)"
export PATH="$SPARKLE_BIN:$PATH"

generate_keys
```

Output looks like:

```
A pair of keys has been generated for you. The public key is:

  abcd1234…long base64 string…XYZ=

This key is required to verify updates. Add it to Info.plist via SUPublicEDKey.

The private key is stored in your Keychain — you don't need to back it up
separately, but DON'T LOSE IT, or you'll have to reset every shipped install.
```

### 2. Export the public key

Add this line to `~/.zshrc` (or your shell rc):

```bash
export SPARKLE_PUBLIC_KEY="<the long base64 string from step 1>"
```

Then `source ~/.zshrc` so it's set in your current shell. `build-app.sh` reads this var and embeds it in the bundled Info.plist's `SUPublicEDKey`.

### 3. Verify the embedded key

```bash
./build-app.sh
plutil -p PurpleDedup.app/Contents/Info.plist | grep SUPublicEDKey
```

The output should show your public key, NOT `PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY`. If it's still the placeholder, your env var isn't being read — re-source your shell rc and rebuild.

### 4. Set up notarization (strongly recommended)

Without notarization, Gatekeeper shows users on a clean Mac a "developer cannot be verified" dialog the first time they try to open the app. They have to right-click → Open to bypass it. With notarization, every release just works on first launch.

**Step 1.** Create an app-specific password at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords. Label it something like "PurpleDedup notarization." Save the long generated password.

**Step 2.** Store it in the keychain as a notarytool profile:

```bash
xcrun notarytool store-credentials "PurpleDedup-Notary" \
    --apple-id you@example.com \
    --team-id SRKV8T38CD \
    --password <the app-specific password from step 1>
```

The `team-id` should match your Developer ID Application certificate's team ID — `security find-identity -v -p codesigning` will show it. The profile name (`PurpleDedup-Notary`) is arbitrary; just match it in step 3.

**Step 3.** Add to your shell rc (`~/.zshrc`):

```bash
export NOTARIZE_PROFILE="PurpleDedup-Notary"
```

Then `source ~/.zshrc`.

**Step 4.** Verify the next release notarizes. `./Scripts/release.sh` should now print:

```
Notarizing with profile: PurpleDedup-Notary
…
Notarization accepted.
Stapling ticket to PurpleDedup.app…
…
Notarization ticket verified (stapler validate ✓)
Notarized: yes
  ↳ Gatekeeper-clean — first launch on any Mac just works
```

If the verdict is `Notarized: no` even with `NOTARIZE_PROFILE` set, check `/tmp/notarize.plist` for the notarytool error message — common causes are an expired Developer ID cert (`security find-identity -v -p codesigning` shows expiration) or an app-specific password that's been revoked from the Apple ID page.

### 5. (Optional) GitHub Releases auth

The release script uses `gh` (GitHub CLI) to upload the zip to a tagged release. Authenticate once:

```bash
gh auth login
```

If you'd rather host the zip elsewhere (Pages, S3, etc.), edit the `DOWNLOAD_URL` in `Scripts/release.sh`.

## Per-release flow

```bash
./Scripts/release.sh
```

Does the following:

1. Warns if `NOTARIZE_PROFILE` is unset and gives you 5 seconds to abort. Otherwise builds with notarization on.
2. Builds `PurpleDedup.app` via `build-app.sh` (with your `SPARKLE_PUBLIC_KEY` baked in and notarization on if `NOTARIZE_PROFILE` is set).
3. Zips the bundle as `~/Downloads/PurpleDedup release/PurpleDedup-<version>.zip`.
4. Signs the zip with `sign_update` (reads the EdDSA private key from Keychain).
5. Generates an appcast `<item>` snippet at `~/Downloads/PurpleDedup release/appcast-snippet.xml`.
6. Prints next-step instructions:
   - Paste the snippet into `PurpleDedup/appcast.xml` as the FIRST `<item>`.
   - `gh release create purplededup-v<version> --title "…" "<zip>"`.
   - `git add PurpleDedup/appcast.xml && git commit && git push origin main`.

That's it. Existing users see the update on next launch (or up to 24 h later if automatic checks are enabled).

## How Sparkle decides whether to offer an update

- The shipped Info.plist points at `https://raw.githubusercontent.com/bronty13/PhantomLives/main/PurpleDedup/appcast.xml`.
- On launch (and every 24 h thereafter when auto-check is on), Sparkle fetches that file.
- It picks the highest-`<sparkle:shortVersionString>` `<item>` whose `<sparkle:minimumSystemVersion>` allows the user's macOS, and compares it to the running app's `CFBundleShortVersionString`.
- If newer, it downloads the `<enclosure url=…>`, verifies the EdDSA signature against the embedded `SUPublicEDKey`, and offers to install.

If the signature fails, Sparkle refuses the update and logs the reason. **This is the trust chain — never edit a shipped `<item>`'s version + signature pair after publishing.**

## What can go wrong

- **"Update is improperly signed"** in the Sparkle UI → either the private key isn't in your Keychain (re-run `generate_keys`), or the public key in Info.plist doesn't match (`SPARKLE_PUBLIC_KEY` got out of sync).
- **"Could not parse update feed"** → invalid XML in `appcast.xml`. Validate with `xmllint --noout PurpleDedup/appcast.xml`.
- **"This update is for a newer version of macOS"** → the `<sparkle:minimumSystemVersion>` in the latest `<item>` is higher than the user's OS. Drop the constraint or ship a separate older-OS feed.
- **Sparkle never finds the new release** → check that the appcast was actually pushed to `origin/main` and that `raw.githubusercontent.com` is serving the new file (browser cache + CDN may take a minute).

## Forgetting / rotating the key

If the private key is lost (Keychain wipe, machine replacement) or compromised:

1. `generate_keys` to make a new pair.
2. Update `SPARKLE_PUBLIC_KEY` in your shell rc.
3. Ship a release with the new key embedded.

Existing installs running the OLD public key will refuse the new release as unsigned — they'll need a manual re-download from your GitHub Releases page. There's no in-app way around this; the trust chain is by design.
