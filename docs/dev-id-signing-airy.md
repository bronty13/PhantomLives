# Developer-ID signing on a headless Mac (airy) — stable TCC grants across rebuilds

## Why

Apps built on a Mac **without** a Developer ID fall back to **adhoc** signing. Adhoc gives the binary
a **new code hash (cdhash) on every build**, and macOS keys TCC privacy grants (Full Disk Access,
Photos, Removable Volumes, Automation…) to that hash. So **every rebuild silently invalidates the
grants** — the app shows phantom "permission needed" errors while System Settings still lists it as
granted, and you must remove-and-re-add it each time. On the **airy** runner (frequent rebuilds over
SSH) this was a constant tax.

A **Developer-ID signature** gives the app a **stable code identity** (Team ID + cert), so its TCC
designated requirement doesn't change between builds → **grants survive rebuilds**. Notarization is
**not** required for this — it only matters for distributing to *other* Macs' Gatekeeper. A local
runner just needs the signature.

The obstacle: Dev-ID `codesign` needs the signing key from a keychain, and over SSH the **login**
keychain is unreachable (`errSecInternalComponent`). The fix is a **dedicated signing keychain** with
`set-key-partition-list` so `codesign` can use the key non-interactively over SSH.

## One-time setup (per headless Mac)

1. **Export the Dev-ID identity** (cert + private key) from a Mac that has it, as a password-protected
   `.p12`: `security export -k login.keychain-db -t identities -f pkcs12 -P <p12pw> -o devid.p12`
   (run with the sandbox disabled so it can read the login keychain), then copy it over.
2. **Create the signing keychain** and import the identity (choose a keychain password `KCPW`):
   ```sh
   KC="$HOME/Library/Keychains/purple-signing.keychain-db"
   security create-keychain -p "$KCPW" "$KC"
   security set-keychain-settings "$KC"                       # no inactivity auto-lock
   security unlock-keychain -p "$KCPW" "$KC"
   security import devid.p12 -k "$KC" -P "$P12PW" -T /usr/bin/codesign -T /usr/bin/security
   security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPW" "$KC"   # non-interactive codesign
   security list-keychains -d user -s "$KC" $(security list-keychains -d user | sed 's/"//g')
   rm -f devid.p12
   ```
3. **Store the keychain password** so unattended builds can unlock it:
   ```sh
   mkdir -p ~/.config/purple-signing
   printf '%s' "$KCPW" > ~/.config/purple-signing/keychain-pw && chmod 600 ~/.config/purple-signing/keychain-pw
   ```
   The password only guards the key **at rest**; the key already lives on the machine, so a 600-perm
   file is the standard trade-off (same as CI runners).

## How `build-app.sh` uses it

`detect_codesign_identity()` over SSH: if `~/.config/purple-signing/keychain-pw` +
`~/Library/Keychains/purple-signing.keychain-db` exist, it **unlocks that keychain and Dev-ID-signs**;
otherwise it **falls back to adhoc** (so remote builds still work anywhere the keychain isn't set up).
`SIGN_KEYCHAIN` / `SIGN_KC_PW_FILE` env vars override the paths; `FORCE_DEVID=1` forces the
login-keychain path instead.

## The one transition cost

Switching an app from adhoc → Dev-ID is itself an identity change, so the **first** Dev-ID rebuild
invalidates the existing (adhoc-keyed) grants **one last time** — re-grant once. **Every rebuild after
that keeps the grants.**

## Verify

```sh
codesign -dv /Applications/<App>.app 2>&1 | grep -E "Authority|TeamIdentifier"
# → Authority=Developer ID Application: Robert Olen (SRKV8T38CD) ; TeamIdentifier=SRKV8T38CD
```

Adhoc shows no `TeamIdentifier` / `Signature=adhoc`.

## Propagation

The signing block is reusable — copy the `SIGN_KEYCHAIN` / `unlock_signing_keychain` /
`detect_codesign_identity` block into any other PhantomLives `.app` `build-app.sh` that gets rebuilt on
a headless Mac (PurpleMirror, etc.). Reference: `PurpleAttic/build-app.sh`.
