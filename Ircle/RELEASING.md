# Releasing Ircle

Ircle auto-updates via **Sparkle 2**. A release is a notarized + stapled
`Ircle.app`, zipped, EdDSA-signed, attached to a tagged GitHub release, and
announced in `appcast.xml` — pushing that file is what makes existing installs
offer the update.

Cut a release with:

```sh
./Scripts/release.sh
```

It is machine-independent and fully guarded (pre-flight checks, build +
notarize + staple, Gatekeeper assessment, zip + EdDSA-sign, GitHub release,
appcast prepend + push). Version is **git-derived** (`1.0.<commit-count>`,
tag `ircle-v<version>`) — no manual bump; release from a committed, pushed `main`.

## One-time setup per Mac

These live in the **login Keychain / shell rc** and do **not** sync between the
two Macs — set them up on each.

1. **Developer ID Application certificate** — must appear in
   `security find-identity -v -p codesigning`. (Shared across all PhantomLives
   apps; already present on the release machine.)

2. **notarytool keychain profile.** `Scripts/release.sh` defaults to
   `PurpleDedup-Notary` (the shared profile already on the release Mac — one
   Apple-ID/team profile notarizes any app). To create one:
   ```sh
   xcrun notarytool store-credentials "PurpleDedup-Notary" \
       --apple-id <your-apple-id-email> \
       --team-id  SRKV8T38CD \
       --password <app-specific-password from appleid.apple.com>
   ```
   Override the name via `NOTARIZE_PROFILE=… ./Scripts/release.sh`.

3. **Sparkle EdDSA key — the shared PhantomLives fleet key.** Ircle reuses the
   same keypair as PurpleDedup/PurpleIRC (so `build-app.sh` embeds the public
   half via `SPARKLE_PUBLIC_KEY` from your shell rc, and `release.sh` signs the
   zip with the private half from the Keychain).
   - The public half is exported in `~/.zshrc`:
     `export SPARKLE_PUBLIC_KEY="2q4I3WNk7qQbidXEO/Jo/U3+t2ODS9x+e3/Wqt+ClQQ="`
   - The **private** half must be in this Mac's login Keychain. To move it from
     the Mac that has it:
     ```sh
     SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -type d | head -1)"
     # on the Mac that HAS the key:
     "$SPARKLE_BIN/generate_keys" -x /tmp/sparkle_key.pem
     # on THIS Mac:
     "$SPARKLE_BIN/generate_keys" -f /tmp/sparkle_key.pem
     ```
   `release.sh` refuses to proceed if the Keychain's private key doesn't match
   `SPARKLE_PUBLIC_KEY` (guards against signing an update installs won't trust).

## Notes

- Routine `./build-app.sh` (no `SPARKLE_PUBLIC_KEY`) embeds a placeholder; the
  app launches fine but `UpdaterController` keeps the updater **off** (the "Check
  for Updates…" menu greys out) — it never crashes on a missing key.
- `appcast.xml` lives at the subproject root and is served via
  `raw.githubusercontent.com`. Never hand-edit a shipped `<item>` — the
  version + `sparkle:edSignature` pair is part of the trust chain.
- The CHANGELOG headings use `## 0.x.y` while the shipped version is git-derived
  `1.0.<count>`, so `release.sh` falls back to generic release notes ("See
  CHANGELOG.md"). That's fine; the CHANGELOG is the source of truth.
