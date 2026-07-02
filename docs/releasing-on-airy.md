# Releasing on airy — cut a formal release from the runner over SSH

> Workstream 1 of `docs/airy-services-plan.md`. Lets you cut a Sparkle release from any Mac
> without tying up your workstation: `release-on-airy.sh` runs a subproject's own
> `Scripts/release.sh` on airy over SSH, handling the headless keychain + env differences.

## Why a wrapper (and why no per-app `release.sh` edit)

Each app's `Scripts/release.sh` is designed to run from either workstation and reads three
secrets from **keychains that are LOCKED on a fresh SSH session**:

- the **Developer ID** cert (`security find-identity -v -p codesigning`),
- the **notarytool** profile (`xcrun notarytool --keychain-profile`),
- the **Sparkle** EdDSA signing key (`sign_update` / `generate_keys -p`).

`docs/dev-id-signing-airy.md` already put the Dev-ID in the dedicated `purple-signing` keychain
**and added it to the keychain search list** — so `find-identity` finds it *once the keychain is
unlocked*. The only missing step over SSH is the unlock. Rather than edit 7 diverged `release.sh`
copies (risking the working Vortex/MB14 flow), `release-on-airy.sh` unlocks centrally, then calls
the unchanged `release.sh`. `build-app.sh` (invoked by `release.sh`) independently unlocks
`purple-signing` too, so signing is covered end-to-end.

## Usage

```sh
# Notarized Sparkle release of PurpleMirror, run on airy:
AIRY_SSH=you@airy.local ./release-on-airy.sh PurpleMirror

# Pass release.sh flags/env through (env vars are forwarded as remote exports):
AIRY_SSH=you@airy.local ALLOW_DIRTY=1 ./release-on-airy.sh PurpleIRC

# Inspect exactly what would run on airy, without connecting:
./release-on-airy.sh --print-remote PurpleMark
```

| Env | Default | Meaning |
|---|---|---|
| `AIRY_SSH` | *(required)* | ssh target, e.g. `you@airy.local` (key auth; `BatchMode` — never prompts) |
| `AIRY_REPO` | `~/dev/PhantomLives` | repo path on airy |
| `AIRY_BRANCH` | `main` | branch to release from (`release.sh` requires `main`, clean, pushed) |
| `SIGN_KEYCHAIN` / `SIGN_KC_PW_FILE` | `~/Library/Keychains/purple-signing.keychain-db` / `~/.config/purple-signing/keychain-pw` | signing keychain to unlock |
| `LOGIN_KC_PW_FILE` | *(unset)* | if set, also unlock the **login** keychain (see notary/Sparkle below) |

Forwarded release env vars (set them in the caller's environment): `GITHUB_REPO`,
`NOTARIZE_PROFILE`, `SPARKLE_PUBLIC_KEY`, `SHORT_VERSION`, `BUILD_NUMBER`, `ALLOW_DIRTY`,
`ALLOW_UNNOTARIZED`. Positional args (e.g. `--no-install`) pass straight to `release.sh`.

## One-time airy setup

The signing keychain is done (`dev-id-signing-airy.md`). For **notarized Sparkle** releases,
airy also needs the notary profile and the Sparkle key reachable over SSH:

1. **notarytool profile** — store the shared PhantomLives profile:
   ```sh
   xcrun notarytool store-credentials PurpleDedup-Notary \
     --apple-id <apple-id> --team-id SRKV8T38CD --password <app-specific-password>
   ```
   (an **app-specific** password, not the account password.)
2. **Sparkle key** — import the *canonical shared* EdDSA private key into airy's keychain
   (`.../Sparkle/bin/generate_keys -f <key>`), and export the matching `SPARKLE_PUBLIC_KEY` in
   `~/.zprofile`. `release.sh` hard-fails on a key mismatch, so this must be the same key every
   other install trusts — a wrong key ships an update nothing can install.
3. **`gh`** — `gh auth login` on airy (or a `GH_TOKEN` in the env).
4. **Unlocking notary + Sparkle over SSH.** Both live in the **login** keychain, which a fresh
   SSH session leaves locked. Two options:
   - **Simplest:** set `LOGIN_KC_PW_FILE=~/.config/purple-signing/login-pw` (a 600-perm file with
     the login-keychain password) so the wrapper unlocks it. Same at-rest trade-off as the signing
     keychain pw file.
   - **Or** store the notary profile + Sparkle key in the `purple-signing` keychain instead and
     keep the login keychain out of it (more setup, no login-keychain password on disk).

## Verify

```sh
./release-on-airy.sh --print-remote PurpleMirror   # eyeball the remote script
AIRY_SSH=you@airy.local ALLOW_UNNOTARIZED=1 ./release-on-airy.sh PurpleMirror --no-install  # dry-ish
```
A real run ends with `release.sh` printing the GitHub release URL and `Notarized: yes`, and the
appcast commit pushed. Tests: `./tests/test_release_on_airy.sh` (renders the remote script and
asserts the unlock/sync/env-forwarding shape — no SSH needed).
