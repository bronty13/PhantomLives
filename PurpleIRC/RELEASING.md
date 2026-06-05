# Releasing PurpleIRC

PurpleIRC **auto-updates via [Sparkle 2](https://sparkle-project.org/)**. A
release is a **notarized, stapled `.app`, zipped, EdDSA-signed, attached to a
tagged GitHub release, and announced in `appcast.xml`** — the appcast is what
makes existing installs offer the update (on launch + every 24h, or via
**PurpleIRC ▸ Check for Updates…**). The zip is independently usable too:
notarization lets someone download it on a clean Mac and open it without the
*"developer cannot be verified"* Gatekeeper dialog.

The whole flow is one command:

```bash
./Scripts/release.sh
```

…once the one-time per-machine setup below is done. It builds + notarizes +
zips + EdDSA-signs the app, creates the GitHub release, then prepends an
`<item>` to `appcast.xml` and pushes it — so the update goes live in one shot.

## Two machines, one process

The maintainer develops on two Macs — **Vortex** and **MB14** (reached over an
SMB mount). `Scripts/release.sh` is **machine-independent**: it uses whatever
Developer ID certificate and notarytool profile *that* Mac has in its login
Keychain. Those credentials live in the Keychain and are **not** synced between
machines, so the one-time setup below must be done **once on each Mac you ever
cut a release from**. After that, `./Scripts/release.sh` produces a byte-for-
byte-equivalent notarized artifact on either machine — it does not matter which
one you release from.

You do **not** need the SMB mount for releasing. It is only how you move
between machines; the release itself reads nothing from it.

## One-time setup (per Mac)

You only do these once per machine. After that, every release is just
`./Scripts/release.sh`.

### 1. Developer ID Application certificate

`security find-identity -v -p codesigning` must list a line like:

```
1) E0D6…25B0 "Developer ID Application: Robert Olen (SRKV8T38CD)"
```

`build-app.sh` auto-detects this and signs with it (hardened runtime +
timestamp), which is what makes the bundle notarization-eligible. If it's
missing, download the **Developer ID Application** certificate from
[developer.apple.com](https://developer.apple.com/account/resources/certificates)
(or export+import it from the other Mac) into your login Keychain.

The team ID in the parentheses — **`SRKV8T38CD`** — is the one you'll use for
notarization in step 3.

### 2. App-specific password

Notarization talks to Apple as your Apple ID, but uses a scoped password, not
your real one:

1. Go to [appleid.apple.com](https://appleid.apple.com) → **Sign-In and
   Security → App-Specific Passwords**.
2. Create one, label it something like *"PurpleIRC notarization"*.
3. Copy the generated `xxxx-xxxx-xxxx-xxxx` password.

One app-specific password works for any number of notarytool profiles, so you
can reuse the same one you may already have for PurpleDedup.

### 3. Store the notarytool keychain profile

This caches the credentials in the login Keychain under a profile name the
release script looks for (`PurpleIRC-Notary` by default):

```bash
xcrun notarytool store-credentials "PurpleIRC-Notary" \
    --apple-id you@example.com \
    --team-id  SRKV8T38CD \
    --password <the app-specific password from step 2>
```

- `--team-id` must match the team ID from your Developer ID cert (step 1).
- The profile name is arbitrary — if you pick a different one, export it:
  `export NOTARIZE_PROFILE="<your-name>"` (in `~/.zshrc`) so the release script
  finds it.

> **Reusing an existing profile.** A notarytool profile is tied to your Apple
> ID + team, **not** to a specific app — so if you already have a working
> profile on this Mac for another PhantomLives app (e.g. `PurpleDedup-Notary`),
> you can reuse it instead of storing a second one: just
> `export NOTARIZE_PROFILE="PurpleDedup-Notary"` in `~/.zshrc`. The release
> script and `build-app.sh` honor whatever `NOTARIZE_PROFILE` is set to,
> falling back to `PurpleIRC-Notary` only when it's unset. (Confirm it's
> actually stored on *this* machine with
> `xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE"` — a global
> `export` in your rc does nothing if the credentials were only ever stored on
> the *other* Mac.)

Verify it took:

```bash
xcrun notarytool history --keychain-profile "PurpleIRC-Notary"
```

(prints your submission history — empty is fine on first setup; an *error*
means the profile isn't stored).

### 4. GitHub CLI auth

The release script uploads the zip to a tagged GitHub release:

```bash
gh auth status   # should show: Logged in to github.com
gh auth login    # if not
```

### 5. Sparkle update-signing key (EdDSA) — reuse the one you already have

Sparkle verifies every update with an **EdDSA signature**. The **public** half
is embedded in each shipped app (build-app.sh reads `SUPublicEDKey` from
`SPARKLE_PUBLIC_KEY`); the **private** half lives in the login Keychain and
signs the release zip.

Per Sparkle's own tooling: *"You only need one signing key, no matter how many
apps you embed Sparkle in."* The key is stored **per Keychain**, not per app —
so **PurpleIRC reuses the same key PurpleDedup already uses**. You almost
certainly already have it set up. Confirm:

```bash
SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -type d | head -1)"
# (run `swift package resolve` first if .build/artifacts doesn't exist yet)
"$SPARKLE_BIN/generate_keys" -p     # prints the existing public key
echo "$SPARKLE_PUBLIC_KEY"          # should already match, from your ~/.zshrc
```

If both print the same base64 string, you're done — `release.sh` will sign with
the Keychain's private key and shipped apps will verify against it.

**Only if no key exists yet** (`generate_keys -p` errors), create one once:

```bash
"$SPARKLE_BIN/generate_keys"        # private→Keychain, prints public
export SPARKLE_PUBLIC_KEY="<the printed base64>"   # add to ~/.zshrc
```

Verify a build embeds the real key (not the placeholder):

```bash
./build-app.sh --no-install
plutil -p PurpleIRC.app/Contents/Info.plist | grep SUPublicEDKey
```

> ### ⚠️ Both Macs must hold the SAME key
>
> Every shipped copy of PurpleIRC embeds **one** public key, so a release built
> on *either* Vortex or MB14 must be signed with the **same private key**, or
> installs reject the update as "improperly signed." Unlike the Developer ID
> cert and notary profile (independent per machine), the Sparkle key must be
> **identical** on both — and it's the same key PurpleDedup uses, so if you've
> released PurpleDedup from both Macs it's already there.
>
> If one Mac is missing it, copy the key over (the SMB mount is fine for this
> one-off):
>
> ```bash
> # On the Mac that HAS the key — export it:
> "$SPARKLE_BIN/generate_keys" -x /tmp/sparkle_private_key.pem
> # On the other Mac — import it, then delete the file:
> "$SPARKLE_BIN/generate_keys" -f /tmp/sparkle_private_key.pem
> rm /tmp/sparkle_private_key.pem
> ```
>
> Use the **same** `SPARKLE_PUBLIC_KEY` value in both Macs' `~/.zshrc`. Lose the
> private key and you must ship a new key in a new release; every existing
> install then needs a one-time manual re-download — the trust chain is by
> design.

`release.sh` requires `SPARKLE_PUBLIC_KEY` to be set and the matching private
key to be in the Keychain (it runs `sign_update`, which fails loudly otherwise).

## Per-release flow

From a **clean, committed, pushed** `main` (the version is the git commit
count, so the release pins to the exact commit you run it on):

```bash
cd ~/dev/PhantomLives/PurpleIRC
git pull --rebase          # pick up any commits the other Mac pushed
./run-tests.sh             # don't ship a red tree
./Scripts/release.sh
```

`release.sh` then:

1. **Pre-flight** — verifies the Developer ID cert, the `PurpleIRC-Notary`
   profile, `gh` auth, `SPARKLE_PUBLIC_KEY` + `sign_update`, and that you're on
   a clean, pushed `main`. Any missing piece aborts with the exact fix.
2. **Build + notarize** — runs `build-app.sh --no-install` with
   `NOTARIZE_PROFILE` + `SPARKLE_PUBLIC_KEY` set, so the bundle is
   Developer-ID-signed (hardened runtime + timestamp), notarized + stapled, and
   embeds the update public key. It does **not** touch `/Applications` or steal
   focus.
3. **Verify** — `stapler validate` + a Gatekeeper assessment (`spctl -a`). A
   broken notarization fails the release loudly rather than shipping a bundle
   that trips Gatekeeper.
4. **Package + sign** — `ditto -c -k --keepParent` →
   `~/Downloads/PurpleIRC release/PurpleIRC-<version>.zip` (preserves the
   signature), then EdDSA-signs the zip with `sign_update`.
5. **Publish** — tags the commit `purpleirc-v<version>` and creates a GitHub
   release with `gh`, uploading the zip and pulling notes from the matching
   `CHANGELOG.md` heading.
6. **Announce** — prepends a new `<item>` (with the EdDSA signature + the GitHub
   asset URL) to `appcast.xml`, validates it with `xmllint`, then commits and
   pushes it to `main`. The update is live the moment the push lands.

It prints the release URL and the local artifact path when done. Existing
installs see the update on next launch (or within ~24h).

### Version numbers

The version is **git-derived**: `1.0.<whole-repo-commit-count>` (same as
`build-app.sh`). There is no manual bump — committing anything anywhere in the
PhantomLives monorepo advances it. The release tag is `purpleirc-v1.0.<count>`
and the zip is `PurpleIRC-1.0.<count>.zip`. Because the version is the commit
count, **you cannot cut two releases from the same commit** — the script
refuses to clobber an existing tag/release. Make a commit (which bumps the
count) before releasing again.

## What can go wrong

- **`notarytool profile 'PurpleIRC-Notary' not found`** → step 3 wasn't run on
  *this* Mac. Each machine needs its own `store-credentials` (Keychain doesn't
  sync). Run it, then re-release.
- **`stapler validate failed`** → notarization was requested but Apple didn't
  accept the bundle. Read `/tmp/notarize.plist` for the status and
  `/tmp/notarize.log` for the per-issue detail. The usual cause is an
  executable in the bundle signed without `--options runtime` /`--timestamp`,
  or an expired Developer ID cert (`security find-identity -v -p codesigning`
  shows expiry).
- **`HTTP 401` / notarization hangs** → the app-specific password was revoked
  or the Apple ID needs re-auth. Recreate the password (step 2) and re-run
  `store-credentials` (step 3).
- **`release/tag purpleirc-v… already exists`** → you're releasing the same
  commit twice. Commit something (bumps the version) or delete the existing
  release/tag first.
- **`gh` not authenticated** → `gh auth login`.
- **`sign_update failed`** → the EdDSA private key isn't in *this* Mac's
  Keychain. Import it (`generate_keys -f`, see step 5) — it's the same key
  PurpleDedup uses.
- **Users see "Update is improperly signed"** → the public key embedded in
  their installed app doesn't match the private key that signed the zip. Both
  Macs must share one key (step 5); confirm `SPARKLE_PUBLIC_KEY` matches
  `generate_keys -p` on the Mac you released from.
- **Sparkle never finds the new release** → confirm the appcast commit reached
  `origin/main` and `raw.githubusercontent.com/.../PurpleIRC/appcast.xml`
  serves the new `<item>` (CDN + browser cache can lag a minute). Validate the
  feed with `xmllint --noout appcast.xml`.

## Escape hatches (avoid in normal use)

- `ALLOW_DIRTY=1 ./Scripts/release.sh` — skip the clean-tree / on-main /
  pushed checks. The release won't be reproducible from origin; only for
  local experiments.
- `ALLOW_UNNOTARIZED=1 ./Scripts/release.sh` — build + publish without
  notarization when no profile is set up. The zip will trip Gatekeeper on
  clean Macs (users must right-click → Open the first time). Emergencies only.
- `NOTARIZE_PROFILE=<name> ./Scripts/release.sh` — use a profile named
  something other than `PurpleIRC-Notary`.
