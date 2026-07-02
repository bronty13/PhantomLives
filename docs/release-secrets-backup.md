# Backing up PhantomLives release secrets to 1Password

> The Macs that cut releases (Vortex, MB14, **airy**) hold a handful of signing/notary secrets in
> their keychains. Keychains **don't sync** and one of these secrets is **irreplaceable**. This is
> how to export them into a structured bundle you keep in **1Password**, and restore them onto a
> fresh Mac. Tools: `release-secrets-backup.sh` (export) and `release-secrets-restore.sh` (restore),
> both at the repo root.

## The secrets, and how replaceable each is

| Secret | Where it lives | If lost… |
|---|---|---|
| **Sparkle EdDSA private key** | login keychain | **IRREPLACEABLE.** No future build can sign an update that *already-installed* apps trust → every deployed install loses auto-update forever. |
| **Developer ID identity** (cert + key) | `purple-signing` keychain | Cert is re-downloadable from Apple; the private key, if this is the only copy, is not. Back it up. |
| **notarytool app-specific password** | Apple ID account | Re-creatable at appleid.apple.com any time. Convenience to store. |
| **Keychain unlock pw files** | `~/.config/purple-signing/{keychain-pw,login-pw}` | They're your keychain/login passwords — you know them, but the files let SSH releases unlock non-interactively. |
| **gh token** | `gh` config | Re-creatable via `gh auth login`. |

The **Sparkle key** is the whole reason this doc exists. Everything else is recoverable; that one is not.

## Export (run on the Mac that has the secrets)

Run it **at that Mac's own Terminal** — exporting the Dev-ID key and (on some setups) the Sparkle
key can raise a one-time keychain "Allow" prompt that only a GUI session can answer.

```sh
cd ~/dev/PhantomLives
./release-secrets-backup.sh                 # writes ~/Downloads/phantomlives-release-secrets/<host>-<ts>/
```

It writes a bundle (never inside the repo; it refuses that) containing:

```
sparkle-ed25519-private.key   devid-identity.p12         signing-keychain-pw.txt
login-keychain-pw.txt         gh-token.txt               notary-reference.txt
manifest.env                  README-RESTORE.md
```

`manifest.env` holds the non-file fields — Apple ID, Team ID, notary profile name, the Sparkle
**public** key, and **`P12_PASSWORD`** (the random import password for `devid-identity.p12` — the
`.p12` is useless without it). The script prints exactly what it captured and what it couldn't
(the app-specific password is never machine-extracted).

## Put it in 1Password, then delete the bundle

1. Create an item **"PhantomLives Release Secrets (`<host>`)"** (Secure Note or Document).
2. **Attach every file** in the bundle as a document.
3. Copy the `KEY=VALUE` lines from `manifest.env` into the item's fields — **especially `P12_PASSWORD`**.
4. Paste your **notary app-specific password** into the item (see `notary-reference.txt`).
5. Securely delete the on-disk bundle: `rm -rfP <bundle-dir>`.

> Do one bundle per release Mac, or one shared bundle — the Sparkle key + Dev-ID identity are the
> *same* across all of them (that's the point: one key every install trusts), so a single 1Password
> item restores any Mac.

## Restore (on a fresh Mac)

Download the bundle out of 1Password to a temp dir, then, **at that Mac's Terminal**:

```sh
cd ~/dev/PhantomLives
./release-secrets-restore.sh /path/to/downloaded-bundle
```

It imports the Sparkle key (and verifies the public key matches), imports the Dev-ID `.p12` into a
fresh `purple-signing` keychain with the right partition list (per `dev-id-signing-airy.md`),
restores the pw files, re-auths `gh`, and prints the one interactive step left — `notarytool
store-credentials` (which prompts for the app-specific password from 1Password). Then verify with a
`release-on-airy.sh` run (`docs/releasing-on-airy.md`).

Finally, `rm -rfP` the downloaded bundle.

## Rotation note

If you ever rotate the Sparkle key you must re-export **and** re-key every app's `SUPublicEDKey` +
ship an update signed by the *old* key first (so installs migrate) — see Sparkle's docs. In practice
we don't rotate it; we protect it. That's what this backup is for.
