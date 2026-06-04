# Swift app build prerequisites (read before invoking `build-app.sh`)

These two environment requirements bite hard if missed — diagnostics are misleading. Check both before running any subproject's `build-app.sh` and before assuming a tool bug.

## 1. Full Xcode toolchain required for `#Preview` macros

SwiftPM packages that contain `#Preview { … }` blocks compile via the `PreviewsMacros` plugin, which **only ships with full Xcode** — not with Command Line Tools. If `xcode-select -p` returns `/Library/Developer/CommandLineTools`, the build fails partway through compilation with:

```
error: external macro implementation type 'PreviewsMacros.SwiftUIView'
       could not be found for macro 'Preview(_:body:)';
       plugin for module 'PreviewsMacros' not found
```

This is misleading — it looks like a missing dependency. It's a toolchain mismatch.

**Fix without sudo (one-off):** prefix the invocation:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build-app.sh
```

**Fix system-wide (recommended for dev machines):**
```sh
sudo xcode-select -s /Applications/Xcode.app
```

Subprojects currently known to contain `#Preview` blocks: **none** — PurpleDedup carried the last one until it was removed (commit `3b26576`, 2026-05-24), so every SwiftUI subproject now builds under Command Line Tools. Any new SwiftUI subproject is likely to reintroduce them, at which point this requirement applies again; grep for `#Preview` if a build dies with `PreviewsMacros … not found`.

## 2. Sparkle apps need `SPARKLE_PUBLIC_KEY` in the environment

Subprojects that integrate Sparkle (PurpleDedup, and any future app that wants in-app auto-update) read `SPARKLE_PUBLIC_KEY` from the environment at build time and bake it into the bundle's `Info.plist` as `SUPublicEDKey`. If the variable is unset, `build-app.sh` falls back to the literal placeholder `PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY`. Sparkle refuses to initialize with that value and the running app emits:

```
(Sparkle) The provided EdDSA key could not be decoded.
(Sparkle) Fatal updater error (1): The EdDSA public key is not valid for <App>.
```

The user sees "updater failed to start" or the Check for Updates… menu does nothing.

**Recovery options, in priority order:**

1. **Use the existing production keypair.** On the machine where the keypair was originally generated, run `~/.../.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` to print the public half (the private key lives in that Mac's login Keychain). Copy the base64 string to the dev machine and add `export SPARKLE_PUBLIC_KEY="…"` to `~/.zshrc`, then `source ~/.zshrc` and rebuild.
2. **Generate a fresh dev keypair on the current Mac** if the prod key is unreachable. Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys` once — it mints a keypair, stores the private key in Keychain, and prints the public key. Persist via `~/.zshrc` as above. Trade-off: locally-built bundles will not verify updates signed by the prod private key (fine for dev iteration; not fine for release).
3. **Strip `SUPublicEDKey` entirely** (last-resort) by setting it to empty in the bundle. Sparkle then never initializes; the Updates menu items go dead but everything else works. Use only for one-off testing.

Subprojects currently known to embed Sparkle: **PurpleDedup**.

## 3. ` 2`-suffixed dupes in `.build/` are iCloud corruption, not SwiftPM bugs

If `.build/checkouts/` contains sibling ` 2`-suffixed copies (`Sparkle 2/`, `GRDB 2.swift/`, etc.) and the build fails with `the package manifest at … cannot be accessed`, the cause is almost always iCloud Drive syncing `.build/` between machines and renaming conflicts. See `docs/cross-mac-dev-setup.md` — the repo must live outside `~/Documents/`. Recovery is `rm -rf .build` and rebuild, but the underlying problem will reappear if the repo is still inside an iCloud-managed path.

Other causes of the same symptom (rarer):

- **Interrupted SwiftPM mid-fetch.** `pkill swift-build` or Ctrl-C during dependency resolution can also leave `.build/checkouts/` half-baked. Same fix.
- **Renamed user account.** `.build/` caches absolute paths referencing `/Users/<old>/...`; rename invalidates them. Same fix.
