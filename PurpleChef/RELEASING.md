# Releasing Purple Chef

One command from the release machine:

```bash
cd PurpleChef
scripts/release.sh            # releases the version in package.json
```

That builds + notarizes the macOS DMG locally, pushes the `purplechef-v<ver>`
tag, and GitHub Actions builds the Windows installer and publishes the
release. End state: a published GitHub release with both platforms attached.

## Before you run it

1. **Bump the version** in `package.json` (this is the single source of
   truth — the app's About line, artifact names and tag all derive from it).
2. **Write the `## <version>` CHANGELOG.md entry** (the script hard-fails
   without it) and update README/USER_MANUAL if behavior changed.
3. **Commit and push to `main`.** The script refuses dirty trees, non-main
   branches, and unpushed commits.

## What release.sh does

| Step | Detail |
|---|---|
| Pre-flight | version ↔ CHANGELOG consistency, clean pushed main, tag not taken, Developer ID cert present, notarization creds present, `gh` authed, `npm test` (49) + `npm run typecheck` green |
| Build | `npm run dist:mac` → universal2 (arm64 + x64) `.app`, Developer-ID-signed with hardened runtime |
| Notarize | `scripts/notarize.cjs` (electron-builder `afterSign`): submits via `notarytool` using the `NOTARIZE_PROFILE` keychain profile, then staples the `.app` |
| Verify | `codesign --verify --deep --strict`, `stapler validate`, `spctl --assess` — a build that fails Gatekeeper never ships |
| DMG | staples + validates the DMG itself |
| Tag | annotated `purplechef-v<version>` pushed to origin → triggers CI |
| Upload | creates/reuses the draft release, uploads DMG + ZIP (+ blockmap/latest-mac.yml for a future auto-updater) |

## What CI does (`.github/workflows/release-purplechef.yml`)

On the `purplechef-v*` tag: creates/reuses the draft release, builds the NSIS
`Purple Chef Setup <ver>.exe` on `windows-latest` (typecheck + tests run there
too — a second OS exercising the suite), uploads it, then flips the release
draft → published. Windows artifacts are **not code-signed** (no Windows
cert yet), so SmartScreen warns on first run; the release notes tell users
**More info → Run anyway**.

Monitor / retry:

```bash
gh run list --workflow release-purplechef.yml
gh run watch                       # live view of the latest run
gh release view purplechef-v1.0.1
```

If only the Windows leg failed, re-run the workflow from the Actions tab (or
`gh run rerun <id>`) — the release and mac artifacts are reused, nothing is
duplicated.

## One-time machine setup (macOS side)

Already done on this Mac (see `docs/cross-mac-dev-setup.md` for the two-Mac
context):

- **Developer ID Application** certificate in the login keychain
  (team `SRKV8T38CD`). electron-builder discovers it automatically.
- **notarytool keychain profile** — created once with
  `xcrun notarytool store-credentials <name> --apple-id … --team-id SRKV8T38CD`
  and exported as `NOTARIZE_PROFILE` in `~/.zshrc` (the fleet-wide profile
  name is `PurpleDedup-Notary`; profiles are per Apple ID + team, not per
  app). Alternative: export `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`,
  `APPLE_TEAM_ID` instead.
- **`gh` authenticated** as the repo owner.

Local dev builds are unaffected by any of this: `./build-app.sh` keeps
building adhoc-signed (`identity=null`), and `notarize.cjs` skips silently
when no credentials are in the environment.

## Versioning & hygiene

- Tags are subproject-scoped (`purplechef-v*`) per monorepo convention.
- Every release needs its CHANGELOG entry; the script enforces this.
- No auto-updater yet — users download new versions from GitHub Releases.
  The uploaded `latest*.yml`/blockmap files keep the door open for
  electron-updater later without re-cutting old releases.
