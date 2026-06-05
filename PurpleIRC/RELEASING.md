# Releasing PurpleIRC

PurpleIRC has **no in-app auto-updater** (unlike PurpleDedup, which uses
Sparkle). A "release" here is just a **notarized, stapled `.app`, zipped and
attached to a tagged GitHub release**. Notarization is the only thing that lets
someone download that zip on a clean Mac and open it without the *"developer
cannot be verified"* Gatekeeper dialog.

The whole flow is one command:

```bash
./Scripts/release.sh
```

…once the one-time per-machine setup below is done.

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
   profile, `gh` auth, and that you're on a clean, pushed `main`. Any missing
   piece aborts with the exact fix.
2. **Build + notarize** — runs `build-app.sh --no-install` with
   `NOTARIZE_PROFILE` set, so the bundle is Developer-ID-signed (hardened
   runtime + timestamp), submitted to Apple's notary service, and stapled. It
   does **not** touch `/Applications` or steal focus.
3. **Verify** — `stapler validate` + a Gatekeeper assessment (`spctl -a`). A
   broken notarization fails the release loudly rather than shipping a bundle
   that trips Gatekeeper.
4. **Package** — `ditto -c -k --keepParent` →
   `~/Downloads/PurpleIRC release/PurpleIRC-<version>.zip` (preserves the
   signature; plain `zip` would corrupt it).
5. **Publish** — tags the commit `purpleirc-v<version>` and creates a GitHub
   release with `gh`, uploading the zip and pulling notes from the matching
   `CHANGELOG.md` heading.

It prints the release URL and the local artifact path when done.

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

## Escape hatches (avoid in normal use)

- `ALLOW_DIRTY=1 ./Scripts/release.sh` — skip the clean-tree / on-main /
  pushed checks. The release won't be reproducible from origin; only for
  local experiments.
- `ALLOW_UNNOTARIZED=1 ./Scripts/release.sh` — build + publish without
  notarization when no profile is set up. The zip will trip Gatekeeper on
  clean Macs (users must right-click → Open the first time). Emergencies only.
- `NOTARIZE_PROFILE=<name> ./Scripts/release.sh` — use a profile named
  something other than `PurpleIRC-Notary`.
