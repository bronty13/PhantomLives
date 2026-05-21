# Purple PDF — Handoff

This document is for whoever inherits Purple PDF after 1.0.0. It assumes
you've read [README.md](../README.md) and [DESIGN.md](DESIGN.md).

## 1. Ownership

- **Repo**: `github.com/bronty13/PhantomLives`, subdirectory `PurplePDF/`
  (part of the PhantomLives polyglot monorepo of personal/utility
  projects — see the root `CLAUDE.md` for the shape).
- **Primary maintainer**: Robert Olen (`bronty13` on GitHub).
- **License**: UNLICENSED (private). Treat this as proprietary unless /
  until a license is added.

## 2. Build & Sign Credentials

| Secret | Used by | How to set |
| --- | --- | --- |
| `APPLE_ID` | macOS notarization | env var or CI secret |
| `APPLE_APP_SPECIFIC_PASSWORD` | macOS notarization | app-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | macOS notarization | your dev team id |
| `WIN_CSC_LINK` | Windows code-signing | path or HTTPS URL to .p12 |
| `WIN_CSC_KEY_PASSWORD` | Windows code-signing | the .p12 password |
| `GH_TOKEN` | `electron-builder` publish step | scoped `repo` PAT |

Locally for macOS: import the Developer ID Application cert into the
default Keychain, then `npm run dist:mac`.

## 3. Release Process

1. From `main`, ensure the working tree is clean.
2. Decide the version. Manual minor / major: bump
   `package.json` and prepend a `## [X.Y.0] - YYYY-MM-DD` heading to
   `CHANGELOG.md`. Patch bumps happen automatically via the
   `pre-commit` hook.
3. `git tag -a vX.Y.Z -m "Purple PDF X.Y.Z"`
4. `git push origin main --tags`
5. CI (or local) `npm run dist:mac` + `npm run dist:win`. Output ends
   up in `dist/`.
6. Upload artifacts to the GitHub release matching the tag; the
   auto-updater will pick them up at the next user-launched check.

## 4. File Layout — at a Glance

```
PurplePDF/
  package.json
  build-app.sh              # PhantomLives convention: build host-arch .app + chain to install.sh
  install.sh                # PhantomLives convention: quit, replace /Applications/Purple PDF.app, relaunch
  resources/                # extraResources — fonts + tesseract (shipped at runtime)
  build/                    # electron-builder buildResources — mac/win icon assets,
                            # entitlements, icon generator (NOT shipped at runtime)
  scripts/
    build-app.sh            # universal2 release build (npm run dist:mac); separate from the root convenience script
    build-app.ps1           # windows release build
    install-and-launch.sh   # legacy dev convenience (mac); kept as a thin wrapper for back-compat
    install-pdf-service.sh  # stand-alone installer for the macOS PDF Service shortcut
    install-git-hooks.sh    # installs pre-commit at repo root
    bump-and-log.mjs        # auto-version + changelog
    notarize.cjs            # post-pack notarize hook
  src/
    main/                   # Electron main
    preload/                # contextBridge
    renderer/src/           # React UI
  tests/unit/               # vitest
  docs/                     # this folder
  electron-builder.yml      # packaging config (or `build` in package.json)
```

## 5. Where User Data Lives

`app.getPath('userData')` resolves to:

- macOS: `~/Library/Application Support/Purple PDF/`
- Windows: `%APPDATA%\Purple PDF\`

Within that folder:

| Path | Purpose |
| --- | --- |
| `recents.json` | recent files list |
| `prefs.json` | user prefs (zoom default, last-used tool, …) |
| `autosaves/<sha1>.json` | per-document crash snapshot |
| `Captures/` | screen-capture exports |
| `CrashReports/` | local minidumps |

Wiping any of these is safe; the app rebuilds on next launch.

## 6. Debugging

- **Renderer DevTools**: `⌥⌘I` (mac) or `Ctrl-Shift-I` (win). Disabled
  in production builds; re-enable via `PURPLE_PDF_DEVTOOLS=1`.
- **Main-process logs**: written to
  `<userData>/logs/main.log` via `electron-log`.
- **Crash reports**: `Help → Show Crash Reports Folder`. Minidumps are
  parseable with `minidump_stackwalk` (`brew install breakpad`).
- **Resource paths**: `console.log(window.purplePDF.assetUrl('fonts/NotoSans-Regular.ttf'))`
  should resolve in both dev and packaged builds.
- **Tesseract trace**: set `PURPLE_PDF_OCR_DEBUG=1` to log per-page
  recognition stats.

## 7. Extending Purple PDF

### Add a new IPC handler
1. Declare it in `src/main/index.ts` via `ipcMain.handle('foo:bar', …)`.
2. Expose it in `src/preload/index.ts` via `contextBridge.exposeInMainWorld`.
3. Type it in `src/preload/api.d.ts`.
4. Consume via `window.purplePDF.foo.bar(…)` from any feature module.

### Add a new annotation tool
1. Create `src/renderer/src/features/annotate/tools/<tool>.tsx`.
2. Register it in `tools/index.ts` (id, label, cursor, factory).
3. Add to the **Annotate** menu in `src/main/index.ts`.
4. Implement `flatten` in `src/renderer/src/features/annotate/flatten.ts`
   so it bakes onto the page on save.

### Add a new menu item
Everything menu-side lives in `src/main/index.ts`. Build the
`MenuItemConstructorOptions`, give it a `click` that sends an IPC event,
and have `App.tsx` subscribe via `window.purplePDF.on('menu:…', …)`.

### Add a bundled resource
1. Drop the file under `resources/<subdir>/`.
2. Reference it via `window.purplePDF.assetBytes('<subdir>/<file>')` or
   `assetUrl('<subdir>/<file>')`.
3. `extraResources` in `package.json` already covers everything under
   `resources/` — no config change needed.

### Add a new Tesseract language
1. `git lfs` or otherwise add the `.traineddata.gz` to
   `resources/tesseract/`.
2. Update the OCR panel language dropdown (`src/renderer/src/features/ocr/OCRPanel.tsx`).
3. Pass the language code through to `createWorker(<code>, …)`.

## 8. Dependency Upgrade Cadence

| Dep | Cadence | Notes |
| --- | --- | --- |
| Electron | quarterly | tracking the latest LTS-ish; pin major. |
| pdfjs-dist | bi-monthly | watch for breaking worker-loader changes. |
| pdf-lib | as-needed | small surface; usually safe. |
| tesseract.js | major-only | v6→v7 changed `createWorker` signature. |
| electron-builder | as-needed | watch for `extraResources` / signing regressions. |

Run `npm outdated` monthly, `npm audit` weekly in CI.

## 9. Known Limitations (1.0.0)

Verbatim from `DESIGN.md` — not fixed in 1.0.0:

1. Annotations keyed by original page index (duplicates inherit annots).
2. Move ops identify by original page index (dragging a duplicate may
   move its source).

Both are tracked in `docs/ROADMAP.md` under **1.1.0 — Data model polish**.

## 10. Support Channels

- **Issue tracker** — GitHub Issues on the repo.
- **Bug-report shortcut** in-app — `Help → Report an Issue` opens a
  pre-filled issue template with the app version, OS, and the last 50
  lines of `<userData>/logs/main.log`.
- **Security disclosures** — email the maintainer privately (see §1).
