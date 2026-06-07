# App-icon standard for `.app` subprojects

**Every PhantomLives macOS-app subproject generates its app icon *deterministically
from code at build time* — `Scripts/generate-icon.swift` → `iconutil` →
`AppIcon.icns` — and wires it into the bundle via `CFBundleIconFile`. No binary
icon source (PNG/`.icns`/`.xcassets` blobs) is the source of truth.** A missing or
unwired icon is a ship blocker: an app that shows the generic Swift/AppKit icon in
Finder and the Dock is not done.

This is the same convention already used by PurpleArchive, PurpleMark, Timeliner,
PurpleIRC, PurpleDedup, PurpleVoice, PurpleSpeak, PurpleDiary, PurpleTracker,
WeightTracker, messages-exporter-gui, and (via asset catalog) MasterClipper /
PurpleReel / PurpleLife.

## Why generate from code (the multi-machine reason)

The maintainer works across **two Macs with different usernames**, syncing only
through git at `~/dev/PhantomLives/` (see `docs/cross-mac-dev-setup.md`). A
code-generated icon is the only approach that survives that cleanly:

- **No binary blobs to drift or corrupt.** A checked-in `.icns`/`.png`/`.xcassets`
  is an opaque artifact that can fall out of sync between machines, bloat the repo,
  and — if a checkout ever strays under `~/Documents/` — get iCloud `' 2'`-suffixed
  dupes that silently break the build. `Scripts/generate-icon.swift` is plain text:
  it diffs, reviews, and merges like any other source.
- **Byte-identical on either Mac.** The generator is deterministic (pure AppKit
  drawing, no timestamps/RNG), so every build on every machine produces the same
  icon. There is nothing to "re-export" after editing.
- **Zero per-machine tooling.** It needs only `swift` + `iconutil`, both already in
  the Xcode Command Line Tools that `build-app.sh` requires anyway. No design app,
  no asset pipeline, nothing to install on the second Mac.

Corollary: **do not commit a generated `AppIcon.icns` as the source of truth.**
(A checked-in `Resources/AppIcon.icns` is acceptable *only* as an offline fallback
for the rare host without `iconutil`, as in SlackSucker/PurpleVoice — never as the
primary.) The generator is the source; the `.icns` is a build product.

## The two acceptable wiring mechanisms

Both are fine; pick the one matching the build system.

### A. Loose `.icns` + `CFBundleIconFile` (SwiftPM / hand-rolled Info.plist)

`build-app.sh` renders the iconset, packs it, drops `AppIcon.icns` into
`Contents/Resources/`, and declares it. **The plist must actually carry the key.**

1. Declare it in the *source* `Info.plist` so it is always present:
   ```xml
   <key>CFBundleIconFile</key>
   <string>AppIcon</string>
   ```
   (`AppIcon`, no extension — macOS resolves it to `AppIcon.icns`.)

2. In `build-app.sh`, **set-or-add** — never a bare `Set`:
   ```sh
   ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
   swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
   iconutil -c icns "$ICONSET_DIR" -o "$DEST_APP/Contents/Resources/AppIcon.icns"
   /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$PLIST" 2>/dev/null \
       || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
   ```
   Do the icon install **before** the codesign step so the signature covers the
   modified plist and the `Resources/AppIcon.icns` file.

### B. `Assets.xcassets/AppIcon.appiconset` (XcodeGen apps)

Generate the PNGs straight into the appiconset and let Xcode compile `Assets.car`
and stamp `CFBundleIconName`:

```sh
swift Scripts/generate-icon.swift Sources/<App>/Resources/Assets.xcassets/AppIcon.appiconset >/dev/null
```
with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`. Here the
`.png`s under the appiconset are regenerated build artifacts, not hand-authored —
the generator is still the source of truth. Do **not** mix mechanism A and B in one
app (a loose `.icns` plus an asset catalog fights over which icon wins).

## The bug this standard exists to prevent

`PlistBuddy Set :<key>` **silently no-ops when the key does not already exist** —
it only edits present keys; `Add` is required to create one. Pairing a bare `Set`
with a source plist that never declared `CFBundleIconFile`, plus a `|| true` that
swallows the failure, ships a bundle whose `.icns` sits in `Resources/` with
nothing pointing at it → the generic icon, with a green build and no warning.

> **Incident — PurpleArchive (2026-06-06).** Every build from first release through
> v1.0.714 shipped no icon for exactly this reason: `Set :CFBundleIconFile` against
> a plist lacking the key, `|| true` hiding it. Fixed by declaring the key in the
> source Info.plist *and* switching to set-or-add. An audit of all installed
> siblings found PurpleArchive was the only one affected — the others either bake
> `CFBundleIconFile` into their generated plist or use an asset catalog — but the
> bare-`Set` form is latent in several `build-app.sh` files; harden any you touch.

## Verification (do this every time — headless can't see it)

After an icon change, follow the **Icon / UI change verification sequence** in
`CLAUDE.md`, and additionally *prove the key is wired*, because a window-server is
often unavailable in a headless build session:

1. `./build-app.sh` (build + install + relaunch).
2. `/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "/Applications/<App>.app/Contents/Info.plist"`
   — must print the icon name, not error. (Asset-catalog apps: check
   `:CFBundleIconName` and that `Contents/Resources/Assets.car` exists.)
3. `file "/Applications/<App>.app/Contents/Resources/AppIcon.icns"` → `Mac OS X icon`;
   `sips -g pixelWidth …` → 1024 at the top size.
4. `codesign --verify --deep --strict "/Applications/<App>.app"` — confirms the
   icon install happened before signing.
5. `touch "/Applications/<App>.app" && killall Finder Dock` to bust the icon cache.
6. To eyeball the art headless, render it and look:
   `sips -s format png "…/AppIcon.icns" --out /tmp/icon.png` then open it.
7. Report what you **visually see**, not just that the build succeeded.
