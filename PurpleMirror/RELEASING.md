# Releasing PurpleMirror

PurpleMirror auto-updates via **Sparkle 2**. Cutting a release builds + notarizes
+ EdDSA-signs the app, attaches it to a tagged GitHub release, and prepends a
`<item>` to `appcast.xml` (served via `raw.githubusercontent.com`). Existing
installs offer the update on next launch (or within 24h).

```bash
./Scripts/release.sh      # from a clean, pushed main
```

## One-time per Mac (login Keychain — does NOT sync between Vortex & MB14)

PurpleMirror reuses the **shared PhantomLives** credentials:

1. **Developer ID Application** cert (team `SRKV8T38CD`) in the login keychain —
   `security find-identity -v -p codesigning` must list one.
2. **Notary profile** `PurpleDedup-Notary` (the shared profile):
   ```bash
   xcrun notarytool store-credentials "PurpleDedup-Notary" \
       --apple-id robert.olen@icloud.com --team-id SRKV8T38CD \
       --password <app-specific-password>
   ```
   Override the name with `NOTARIZE_PROFILE=…` if yours differs.
3. **Sparkle EdDSA key** — the *same shared keypair* used across the Purple apps.
   - `export SPARKLE_PUBLIC_KEY="2q4I3WNk7qQbidXEO/Jo/U3+t2ODS9x+e3/Wqt+ClQQ="` in `~/.zshrc`
     (already set on these machines).
   - The matching **private** key must be in this Mac's Keychain. Import from the
     Mac that has it: `"$SPARKLE_BIN/generate_keys" -x /tmp/k.pem` there, then
     `"$SPARKLE_BIN/generate_keys" -f /tmp/k.pem` here. `release.sh` verifies the
     Keychain half matches `SPARKLE_PUBLIC_KEY` before signing.

> Run release/notarize/codesign Bash with the **sandbox disabled** — a sandboxed
> shell can't read the login Keychain and yields a false "profile not stored".

## Rules

- Version is **semantic** (`MAJOR.MINOR.PATCH`, e.g. `1.18.0`) — set it per release via
  `SHORT_VERSION=<x.y.z>` (release.sh/build-app.sh honor the override; release-on-airy.sh
  forwards it). Bump it yourself and add a matching `## <x.y.z> — <date>` CHANGELOG heading
  (release.sh pulls the release notes from the heading that matches `SHORT_VERSION`). The
  **build number** stays git-derived (`<commit-count>.<sha>`) so `CFBundleVersion` is monotonic
  for Sparkle. Release from a committed, pushed commit; re-running on the same tag is refused.
- **Never hand-edit a shipped `<item>`** in `appcast.xml` — its version+signature
  pair is part of the trust chain. Add new items above old ones (release.sh does).
