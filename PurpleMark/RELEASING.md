# Releasing PurpleMark

PurpleMark ships a **notarized DMG** and updates in-app via **Sparkle 2**. One
command — `./Scripts/release.sh` — builds, notarizes, packages, EdDSA-signs,
creates the GitHub release, and updates `appcast.xml`.

This mirrors `PurpleIRC/RELEASING.md`; the credentials below are **shared across
the Purple\* apps**.

## Per-release flow

```sh
cd ~/dev/PhantomLives/PurpleMark
git pull --rebase
./run-tests.sh            # must be green
./Scripts/release.sh      # build → notarize → DMG → release → appcast
```

The version is git-derived (`1.1.<commit-count>`); the tag is
`purplemark-v<version>`. The moment the appcast commit lands on `main`, running
copies are offered the update.

## One-time setup per Mac

1. **Developer ID Application certificate** in the login keychain:
   ```sh
   security find-identity -v -p codesigning
   # must list: "Developer ID Application: Robert Olen (SRKV8T38CD)"
   ```

2. **App-specific password** from appleid.apple.com → Sign-In and Security →
   App-Specific Passwords (use the notarization Apple ID `robert.olen@icloud.com`).

3. **notarytool keychain profile** (shared name `PurpleDedup-Notary`, team `SRKV8T38CD`):
   ```sh
   xcrun notarytool store-credentials "PurpleDedup-Notary" \
       --apple-id robert.olen@icloud.com \
       --team-id SRKV8T38CD \
       --password <app-specific-password>
   ```
   (Override with `NOTARIZE_PROFILE=...` if you use a different profile name.)

4. **GitHub CLI**: `gh auth login`.

5. **Sparkle EdDSA private key** in the login keychain. PurpleMark's public key
   (`SUPublicEDKey` in `Info.plist`) is the **shared** Purple\* key
   `2q4I3WNk7qQbidXEO/Jo/U3+t2ODS9x+e3/Wqt+ClQQ=`, so this Mac must hold the
   matching **private** half. If it's already set up for PurpleIRC/PurpleDedup,
   you're done. Otherwise import it from the Mac that has it:
   ```sh
   # locate Sparkle's tools (after a build/resolve):
   SPK=$(find .build/spm/artifacts -name generate_keys -type f | head -1)
   # on the Mac that HAS the key:
   "$SPK" -x /tmp/sparkle_private_key.pem
   # on THIS Mac:
   "$SPK" -f /tmp/sparkle_private_key.pem
   ```
   > Do **not** run `generate_keys` to make a *new* key — that would change the
   > public key and break updates for everyone on the shared key.

## What `release.sh` does

1. Pre-flight: Developer ID cert, notary profile, `gh` auth, on `main` + clean +
   pushed (override with `ALLOW_DIRTY=1`).
2. Build + sign via `build-app.sh` with `CODESIGN_IDENTITY` (Developer ID,
   hardened runtime; Sparkle's XPCServices/Updater/Autoupdate signed inside-out).
3. Build a DMG (app + `/Applications` symlink) and sign it.
4. Notarize the DMG (`notarytool submit --wait`) and **staple** it.
5. EdDSA-sign the DMG with Sparkle's `sign_update`.
6. `gh release create purplemark-v<version>` with the DMG attached.
7. Prepend a new `<item>` to `appcast.xml`, validate, commit, push.

## Escape hatches

- `ALLOW_DIRTY=1` — skip the clean/pushed checks (local experiments only).
- `ALLOW_UNNOTARIZED=1` — skip notarization (the DMG will trip Gatekeeper; emergencies only).

## Troubleshooting

- **`notarytool profile 'PurpleDedup-Notary' not found`** — run `store-credentials`
  on this Mac (step 3).
- **Notarization failed** — `xcrun notarytool log <submission-id> --keychain-profile PurpleDedup-Notary`.
- **`sign_update produced no signature`** — the Sparkle private key isn't in this
  Mac's keychain (step 5).
- **Users see "Update is improperly signed"** — public/private key mismatch; this
  Mac's private key doesn't match the shared `SUPublicEDKey`.
