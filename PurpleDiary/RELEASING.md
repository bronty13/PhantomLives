# Releasing PurpleDiary

PurpleDiary is a **no-network** app (HANDOFF.md §6, `Docs/SECURITY.md`): no
account, no telemetry, **no in-app updater / no Sparkle / no appcast**. A release
is therefore deliberately *passive* — a notarized, stapled **`.dmg`** attached to
a tagged GitHub release. Users download it, drag the app to Applications, and
**update by re-downloading**. Nothing in a release adds network code to the app;
the only thing that touches the network is the release *script* (the Apple
notarization round-trip + `gh`), running on your dev Mac.

> Why no Sparkle? Sparkle auto-update polls an `appcast.xml` over HTTPS — that is
> exactly the "update-check" egress PurpleDiary forbids (the same reason the
> WeatherKit experiment was reverted). Keeping releases download-only is what lets
> the "PurpleDiary makes no network requests" guarantee stay literally true. If
> that constraint is ever revisited, *that's* the decision to make first — don't
> bolt an updater on without it.

The whole flow is one script: **`Scripts/release.sh`**.

---

## TL;DR — cut a release

```sh
cd PurpleDiary
# commit + push everything first (the script refuses a dirty/unpushed tree)
./run-tests.sh                 # green gate (do this before tagging)
Scripts/release.sh             # build → notarize+staple app → DMG → notarize+staple DMG → GitHub release
```

Run it with the **Bash sandbox disabled** — the sandbox can't read the login
Keychain, which makes `notarytool`/`codesign` report a false "profile not stored"
/ "no identity found" (repo memory: *release-sandbox-keychain*).

Output: `~/Downloads/PurpleDiary release/PurpleDiary-<version>.dmg`, plus a
GitHub release tagged `purplediary-v<version>`.

---

## What the script does (and proves)

1. **Pre-flight** — Developer ID Application cert present; notary profile present;
   `gh` authed; on `main`; the **PurpleDiary subtree** clean; HEAD pushed. (Clean
   is scoped to `PurpleDiary/` — sibling projects in this monorepo don't block.)
2. **Build** — `build-app.sh --no-install` (Developer ID sign + hardened runtime
   + secure timestamp; no `/Applications` touch, no focus-steal). Asserts the
   bundle is Developer-ID-signed, not ad-hoc.
3. **Notarize + staple the app**, then `stapler validate` + `spctl -t exec`.
4. **Build the DMG** (drag-to-Applications layout via `hdiutil`), sign it,
   **notarize + staple the DMG**, then `stapler validate` + `spctl -t open`.
   - Two notarization passes on purpose: stapling writes the ticket *into* the
     artifact so first launch works **offline**, and you can only staple a
     *writable* bundle. So the app is stapled **before** it's sealed into the
     read-only DMG, and the DMG is stapled after. The app stays Gatekeeper-clean
     even after the user drags it out of the DMG — online or off.
5. **Tag + GitHub release** — `purplediary-v<version>`, notes pulled from the
   matching `CHANGELOG.md` section (falls back to `[Unreleased]`, then generic),
   DMG attached.

Version is **git-derived** (`1.0.<repo-commit-count>`), identical to
`build-app.sh` — no manual bump. The release pins to the commit you run it on, so
cut only from a committed + pushed state. Each commit yields a new version, so the
script refuses to clobber an existing `purplediary-v…` tag.

---

## One-time setup per Mac

The signing cert and notary profile live in each Mac's **login Keychain** and do
**not** sync between Vortex and MB14 — do this once on each.

### 1. Developer ID Application certificate

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Must list `Developer ID Application: Robert Olen (SRKV8T38CD)`. If absent, export
it from the Mac that has it (Keychain Access → export `.p12`) and import on the
other. This is the shared PhantomLives signing identity.

### 2. notarytool keychain profile (shared across all PhantomLives apps)

```sh
xcrun notarytool store-credentials "PurpleDedup-Notary" \
    --apple-id robert.olen@icloud.com \
    --team-id  SRKV8T38CD \
    --password <app-specific-password from appleid.apple.com>
```

> The notarization Apple ID is **robert.olen@icloud.com** (the iCloud address, not
> the gmail). The team is **SRKV8T38CD**. One profile — `PurpleDedup-Notary` — is
> reused by every PhantomLives app; you do **not** need a PurpleDiary-specific one.
> (Repo memory: *apple-release-creds*.)

Verify:

```sh
xcrun notarytool history --keychain-profile PurpleDedup-Notary
```

### 3. GitHub CLI

```sh
gh auth status   # or: gh auth login
```

---

## Environment knobs

| Var | Default | Purpose |
|---|---|---|
| `NOTARIZE_PROFILE` | `PurpleDedup-Notary` | notarytool keychain profile name |
| `GITHUB_REPO` | `bronty13/PhantomLives` | release target repo |
| `ALLOW_DIRTY=1` | off | skip clean-tree / pushed checks (NOT recommended) |
| `ALLOW_UNNOTARIZED=1` | off | proceed with no notary profile (DMG trips Gatekeeper; emergencies only) |

---

## Troubleshooting

- **"no Developer ID Application certificate" / "notary profile not found"** but
  you *know* they're installed → you're running under the **Bash sandbox**.
  Disable it; the sandbox can't read the login Keychain.
- **Notarization "Invalid"** → `xcrun notarytool log <submission-id>
  --keychain-profile PurpleDedup-Notary` prints the exact reason (almost always a
  nested binary missing hardened runtime or a timestamp). The submission id is in
  `/tmp/purplediary-notarize-app.log` / `…-dmg.log`.
- **`stapler staple` fails right after an Accepted notarization** → transient
  Apple CDN lag; wait a minute and re-run (the ticket exists, the edge just
  hasn't caught up).
- **Tag already exists** → you're re-running on the same commit. Make a new commit
  (which bumps the git-derived version) or delete the old tag/release first.

---

## Release-hygiene checklist (per CLAUDE.md)

Before running the script:

1. `CHANGELOG.md` has a top entry for this version (or `[Unreleased]` — the script
   reads it for the GitHub notes).
2. `README.md` / `USER_MANUAL.md` reflect any user-facing change.
3. `./run-tests.sh` is green — report the count.
4. Everything committed **and pushed** (the script enforces this).
