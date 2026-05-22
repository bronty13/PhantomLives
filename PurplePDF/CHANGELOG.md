# Changelog

All notable changes to **Purple PDF** are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/spec/v2.0.0.html).

Patch versions increment automatically on every commit that touches
`PurplePDF/**`, via the `pre-commit` hook installed by
`scripts/install-git-hooks.sh`. Minor and major bumps are manual.

## [1.0.3] - 2026-05-21 — Developer ID signing on macOS 15 + iCloud-synced trees

### Fixed
- **`npm run dist:mac` now produces a Developer ID-signed, notarized
  universal2 DMG.** On macOS 15 (Sequoia) the kernel auto-attaches
  `com.apple.provenance` to every executable on first run; hardened-runtime
  `codesign` rejects it as "resource fork, Finder information, or similar
  detritus not allowed." The standard workaround — `xattr -d com.apple.provenance`
  before signing — silently no-ops inside iCloud-synced directories because
  the File Provider intercepts xattr ops. PhantomLives lives under
  `~/Documents/GitHub/…` which is iCloud-synced on most maintainers'
  machines, so codesign failed deterministically. v1.0.2 shipped
  arm64-only adhoc-signed as a workaround.

### Added
- **`scripts/relocate-dist.cjs`** — `predist:mac` hook that symlinks
  `dist/` to a fresh `$TMPDIR/PurplePDF-dist-XXXXXX` before each release
  build. Build output lives on a non-iCloud volume where `xattr -d` works
  normally. The project tree still exposes the conventional `dist/` path
  via the symlink, so DX is unchanged. `$TMPDIR` is wiped on reboot — no
  cleanup needed.
- **`scripts/strip-xattrs.cjs`** — `afterPack` hook that uses
  `find -exec xattr -d` per-file rather than `xattr -cr` (the recursive
  form aborts on the first protected xattr it can't remove). Strips
  `com.apple.FinderInfo`, `com.apple.ResourceFork`, and
  `com.apple.provenance`, then runs a belt-and-suspenders `xattr -cr`.

### Changed
- `dist:mac` script restored to `--mac --universal` (was `--arm64
  --config.mac.identity=null` in v1.0.2 as the adhoc workaround). With
  the `predist` relocate hook in place, signing now works on the
  iCloud-synced tree, so the universal2 release path is the default
  again. Notarization runs via the existing `scripts/notarize.cjs`
  `afterSign` hook when `APPLE_ID` / `APPLE_TEAM_ID` /
  `APPLE_APP_SPECIFIC_PASSWORD` are exported in the build shell.

## [1.0.2] - 2026-05-21 — Stamps, drag-resize, select-tool fixes

### Fixed
- **Select tool can actually move/edit annotations now**. The root cause
  was the `.form-layer` wrapper (z-index 5) using `pointer-events: auto`
  across the whole page whenever the select tool was active — it sat
  invisibly over `.annot-layer` and ate every click before it could
  reach an annotation. The wrapper is now `pointer-events: none` and
  individual form fields opt in on their own rect style.
- **Select tool**: clicking the interior of rectangle, text box, freehand,
  redaction, or signature annotations now reliably selects them.
  Previously clicks inside transparent shapes passed through to the page
  and cleared the selection, making annotations impossible to edit or
  delete.

### Added
- **Drag-to-move** and **8-handle resize** for any selected annotation
  (corners + edge midpoints). Min size 4pt; corners support flipping.
- **Business Stamp tool** with 10 presets — APPROVED, DENIED, REVIEWED,
  RECEIVED, DRAFT, FINAL, CONFIDENTIAL, VOID, REVISED, ✓, ✗ — accessible
  from the ✪ button in the edit palette. Keyboard shortcut: **M**.
- **Adobe-style dynamic stamps**: rounded corners, tinted color fill
  (~14% alpha), single thin border, italic bold label (Helvetica Bold
  Oblique), left-aligned, italic subtitle line
  (e.g. `By Jane Doe at 6:36 pm, May 21, 2026`).
- **Include user** checkbox in the stamp picker, independent of the
  **Include date/time** toggle. The OS username is fetched via the
  `ping.osUser` IPC and prettified (`jdoe` → "J Doe", `jane.doe` →
  "Jane Doe").
- New `purplepdf:ping` field `osUser` and matching preload typing.

### Changed
- Default stamp size bumped to 200×60pt so two lines fit comfortably.
- Saved PDFs render the same look as on-screen (tinted fill + italic
  label + italic subtitle).
- `bump-and-log` test suite is now skipped on Windows where the hook is
  never installed.

## [1.0.1] - 2026-05-20 — Move into PhantomLives monorepo

### Changed
- Imported into the [PhantomLives](https://github.com/bronty13/PhantomLives)
  monorepo as the `PurplePDF/` subproject. Repo references updated from
  `robertolen/glowing-computing-machine` to `bronty13/PhantomLives` in
  `package.json` (`build.publish`), `docs/INSTALL.md`, `docs/HANDOFF.md`,
  and the in-app **Help → Purple PDF User Manual** / **Help → Report an
  Issue** menu URLs (`src/main/index.ts`).
- macOS bundle identifier rebranded to the PhantomLives convention:
  `com.robertolen.purplepdf` → `com.bronty13.purplepdf` (matches every
  other PhantomLives app — see root `CLAUDE.md`). Also updates
  `electronApp.setAppUserModelId(...)` so Windows toast notifications
  bind to the new id.

### Added
- Root-level `build-app.sh` and `install.sh` per the PhantomLives
  `install.sh` standard (root `CLAUDE.md`). Builds host-arch only with
  no DMG / signing dance, auto-chains into `install.sh`, replaces
  `/Applications/Purple PDF.app` via `ditto --noextattr`, strips the
  Gatekeeper quarantine xattr, and relaunches. `--no-install`,
  `--no-open`, and `BUILD_ONLY=1` opt-outs supported. The existing
  `scripts/build-app.sh` (universal2 release DMG) is unchanged.

### Fixed
- **Bundled resources hygiene.** Split `Resources/` (capital-R, mixing
  electron-builder buildResources with `extraResources`) into two
  distinctly-named directories: `build/` for icons + entitlements +
  the icon generator, and `resources/` (lowercase) for runtime extras
  only (`fonts/`, `tesseract/`). Previously, because HFS+ is
  case-insensitive, `extraResources: { from: "resources" }` resolved
  to `Resources/` and shipped the icon generator, master PNG, raw
  `.icns` / `.ico`, and the entitlements plist *inside the .app's
  runtime resources folder*. After the fix, `Contents/Resources/resources/`
  contains exactly `fonts/` and `tesseract/`. Updated `package.json`
  (`buildResources`, mac/win `icon`, `entitlements`,
  `entitlementsInherit`, `fileAssociations.icon`, `scripts.icons`),
  `scripts/build-app.sh`, `scripts/build-app.ps1`, `README.md`,
  `docs/INSTALL.md`, `docs/HANDOFF.md`. `make_icon.py` already used
  `Path(__file__).resolve().parent` so it works from its new home
  unmodified.

## [1.0.0] - 2026-05-20 — General Availability

### Added
- Comprehensive documentation refresh: rewritten `README.md`, expanded
  `docs/USER_MANUAL.md`, new `docs/HANDOFF.md`, updated `docs/DESIGN.md`,
  `docs/INSTALL.md`, `docs/ROADMAP.md`, and this changelog is now the
  single source of truth (`docs/CHANGELOG.md` redirects here).
- Unit tests for `projectOrder` (page-op projection), `autosave` (key
  derivation + listing), and the `bump-and-log` pre-commit script.
- In-file JSDoc tightened on the public renderer/main modules
  (`flatten.ts`, `projectOrder.ts`, `unicodeFont.ts`, `assets.ts`,
  `autosave.ts`, `ocr.ts`).

### Changed
- Marked the project as **General Availability**. Feature surface frozen
  for 1.x; future work tracked as 1.1+ in `docs/ROADMAP.md`.

## [0.9.0] - 2026-05-20

### Added
- **Offline OCR.** `tesseract.js` worker, wasm core, and
  `eng.traineddata.gz` are bundled under `resources/tesseract/` and
  shipped as `extraResources`. OCR runs with zero network access.
- **Bundled Unicode font.** Noto Sans (Regular + Bold) is embedded via
  `@pdf-lib/fontkit` and used for Watermark, Header/Footer/Bates, and the
  invisible OCR text layer — em-dashes, smart quotes, emoji, and CJK now
  render correctly instead of being silently dropped.
- **In-canvas page-op previews.** Pending rotate, delete, duplicate,
  insert-blank, move, and crop operations now reflect immediately in the
  main viewer and the page count, not just in the thumbnail sidebar.
  Save still flattens these to disk.
- **Auto-versioning.** New `pre-commit` git hook bumps the patch version
  in `package.json` and prepends an entry to this file using the staged
  commit subject. Set `SKIP_BUMP=1` to bypass.
- **`pp-asset://` custom protocol** for renderer access to bundled
  resources (registered in `src/main/assets.ts`).

## [0.8.x stretch backlog] - 2026-05-20

Crossed off in a single autopilot push, all included in the 0.9.0 .app:

- Drag-to-reorder pages (with drop indicators).
- Optimize PDF (Ghostscript `/screen|/ebook|/printer|/prepress`).
- Watermark (diagonal, semi-transparent).
- Header/Footer/Bates with `{page}/{total}/{date}/{bates}` tokens.
- Auto-crop margins (pixel-scan via canvas).
- Manual Crop tool (drag-rect to set `cropBox`).
- Compare-two-PDFs side-by-side modal.
- Autosave (debounced 5s) + startup crash-recovery prompt.
- Online OCR (later made offline in 0.9.0).
- Live thumbnail renumbering reflecting queued page ops.

## [0.8.0] - 2026-05-20 — P8 Polish & Distribution

### Added
- **Auto-updater** via `electron-updater` with a GitHub release feed.
  Silent background check on launch; interactive check via
  **Help → Check for Updates…**
- **Crash reporter** writing local minidumps to `<userData>/CrashReports/`.
  Opt out via `PURPLE_PDF_DISABLE_CRASH_REPORTS=1`.
- **Help menu** with User Manual, Keyboard Shortcuts (`⌘/`), Check for
  Updates, Show Crash Reports Folder, Report an Issue, and About Purple PDF.
- macOS hardened-runtime entitlements + notarization scaffold
  (`scripts/notarize.cjs`).
- Publish provider wired in `package.json` (`github`).
- Windows publisher metadata.
- Initial `docs/` quintet.

## [0.7.0] — P7 Standards & Accessibility

- Accessibility Checker sidebar with pass / warn / fail / info severities.
- Document Properties modal (`⌘I`) — Title / Author / Subject / Keywords /
  Language. Saved to info dict and catalog `/Lang`.
- Convert-to-Standard submenu — PDF/A-1b, PDF/A-2b, PDF/A-3b, PDF/X-3 via
  Ghostscript with graceful degradation.
- Keyboard nav polish; `:focus-visible` rings.
- `<html lang>` synced with active document language.

## [0.6.0] — P6 E-signatures & Security

- Sign by Draw / Type / Image; place + resize + flatten on Save.
- AES-256 password protection + per-permission flags via qpdf.
- Certified redaction — visual blackout AND underlying-content removal.
- Metadata strip option on Save.

## [0.5.0] — P5 Forms

- Interactive AcroForm filling.
- Field recognition from flat documents.
- Sandboxed JS hooks: `calculate`, `validate`, `format`.
- FDF / XFDF / JSON / CSV export.

## [0.4.0] — P4 Create & Convert

- Image(s) → PDF (JPEG/PNG/HEIC/TIFF).
- URL → PDF via headless Chromium.
- Scan → PDF via OS scanner.
- Office ↔ PDF via LibreOffice CLI (graceful-degradation).

## [0.3.0] — P3 Print-to-PDF Virtual Printer

- macOS CUPS-based PDF Service shortcut.
- Windows port-monitor "Print to Purple PDF".

## [0.2.0] — P2 Annotate & Edit

- Highlight / Underline / Strikeout / Free Text / Draw / Rectangle / Ellipse
  / Line / Arrow / Sticky Note.
- Undo / redo stacks.
- Page rotate / delete / insert / move.

## [0.1.0] — P1 Viewer MVP

- pdf.js render in multi-tab UI.
- Outline / Thumbnails / Search sidebars.
- `electron-store`-backed Recents.

## [0.0.1] — P0 Scaffold

- Electron + Vite + React + TypeScript scaffold.
- Cross-platform packaging skeleton.
- Purple PDF branding and master 1024×1024 icon.
