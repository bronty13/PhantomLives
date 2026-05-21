# Purple PDF — Design

## Goal

A full-featured, **local-first**, cross-platform PDF reader and editor
implemented on Electron + TypeScript that ships as a single signed
package per platform, with no telemetry and no required online services.

## Engine Strategy

We deliberately did **not** write a PDF engine. We compose three:

| Concern | Engine |
| --- | --- |
| Render to screen | `pdfjs-dist` |
| Mutate / sign / encrypt-light / flatten | `pdf-lib` (+ `@pdf-lib/fontkit`) |
| Standards / Optimize / Office / AES-256 | external CLIs (Ghostscript, qpdf, LibreOffice) — graceful-degradation |
| OCR | `tesseract.js` (offline, bundled) |

Each external CLI has a probe at startup; missing CLIs surface an
install hint in the relevant menu item rather than failing silently.

## Process Model

```
┌────────────────────────────┐       IPC        ┌──────────────────────┐
│ main (Node)                │ ◀──────────────▶ │ preload (contextBridge)│
│  src/main/index.ts         │                  │  src/preload/index.ts  │
│  • menus                   │                  │  exposes window.purplePDF│
│  • IPC handlers            │                  └──────────┬─────────────┘
│  • CLI bridges (gs/qpdf/…) │                             │
│  • crash reporter          │                             ▼
│  • auto-updater            │                  ┌──────────────────────┐
│  • pp-asset:// protocol    │                  │ renderer (React+TS)  │
└────────────────────────────┘                  │ src/renderer/src/App.tsx│
                                                │ features/…           │
                                                └──────────────────────┘
```

## Feature Map (P0 → P10)

| Phase | Status | Highlights |
| --- | --- | --- |
| P0 — Scaffold | ✅ shipped 0.0.1 | Electron + Vite + React + TS, branding, master 1024 icon |
| P1 — Viewer | ✅ shipped 0.1.0 | pdf.js, multi-tab, outline, thumbnails, find, recents |
| P2 — Annotate & Edit | ✅ shipped 0.2.0 | full annotation set; rotate/delete/insert page ops; undo |
| P3 — Print-to-PDF | ✅ shipped 0.3.0 | macOS CUPS PDF Service; Windows port-monitor |
| P4 — Create & Convert | ✅ shipped 0.4.0 | image/URL/scan → PDF; Office ↔ PDF via LibreOffice |
| P5 — Forms | ✅ shipped 0.5.0 | fill, recognize, sandboxed JS, FDF/XFDF/JSON/CSV |
| P6 — E-sign & Security | ✅ shipped 0.6.0 | draw/type/image sig; AES-256; certified redact; metadata strip |
| P7 — Standards & A11y | ✅ shipped 0.7.0 | PDF/A, PDF/X, a11y checker, `/Lang`, focus-visible |
| P8 — Polish & Dist | ✅ shipped 0.8.0 | auto-updater, crash reporter, help menu, notarize, docs |
| P9 — Power Editing | ✅ shipped 0.9.0 | drag-reorder, optimize, watermark, header/footer/bates, auto-crop, manual crop, compare, autosave, offline OCR, bundled Unicode font, **in-canvas previews**, auto-version hook |
| P10 — GA | ✅ shipped 1.0.0 | docs refresh, JSDoc pass, additional unit tests, cleanup |

## Key Architectural Decisions

### Asset protocol — `pp-asset://`
Implemented in `src/main/assets.ts`.

- `registerAssetProtocolScheme()` runs **before** `app.whenReady` with
  privileges `{ standard, secure, supportFetchAPI, bypassCSP,
  corsEnabled, stream }` — required for Worker / fetch / module
  imports.
- `registerAssetProtocolHandler()` runs **after** ready, resolving
  `pp-asset://local/<rel>` to
  `process.resourcesPath/resources/<rel>` in packaged builds and
  `cwd/resources/<rel>` in dev.
- Path safety: `..` and `.` are stripped; absolute prefixes are
  rejected. See `tests/unit/asset-path.test.ts`.

Why a custom protocol instead of `file://`? `file://` cannot be used as
a Worker script source from a non-`file://` page, and we want the
renderer to live on a regular `http(s)://` origin during dev.

### Projected slot model
`src/renderer/src/features/viewer/projectOrder.ts` exposes
`projectPageOrderDetailed(pageOps, originalCount): ProjectedSlot[]`
where each slot is `{ source: number | null, rotation: number, crop? }`.
The legacy `projectPageOrder` returns just the source indices.

`tab.currentPage` was redefined in 0.9.0 to be a **1-based display
position**, not the original page number. `currentSourceIdx` is
derived as `projected[currentPage - 1].source`; blank slots return
`null` and the annotation/form layers are skipped for them.

Tests: `tests/unit/projectOrder.test.ts` covers rotate, crop, delete,
duplicate, insert-blank, move, and combinations.

### Unicode font pipeline
`src/renderer/src/features/text/unicodeFont.ts`:

- Registers `@pdf-lib/fontkit` on each `PDFDocument` via a `WeakSet`
  guard.
- Loads `NotoSans-Regular.ttf` / `NotoSans-Bold.ttf` from
  `resources/fonts/` through `window.purplePDF.assetBytes`.
- `embedUnicodeFont(doc, { bold, fallback })` returns the subsetting
  embedded font; on failure (e.g. corrupt TTF) it falls back to the
  caller-provided Helvetica/HelveticaBold to keep the user flow alive.
- Used by `watermark.ts`, `headerFooter.ts`, and `ocr/ocr.ts`.

### Offline OCR
`tesseract.js@7` `createWorker('eng', undefined, { workerBlobURL: true,
workerPath, corePath, langPath, cacheMethod: 'none' })`. The worker is
fetched as bytes via `pp-asset://` and wrapped in a `Blob` URL so the
WebWorker constraint that the script come from the same origin as the
spawning document is satisfied without weakening renderer security.

### Auto-version hook
`scripts/install-git-hooks.sh` installs `.git/hooks/pre-commit` at the
**repository root** (the parent of `PurplePDF/`).

`scripts/bump-and-log.mjs` reads the staged file list (`git diff
--cached --name-only`) and **no-ops** unless at least one path is under
`PurplePDF/`. Otherwise it bumps the patch, prepends an entry to
`CHANGELOG.md`, and re-stages both files. Set `SKIP_BUMP=1` to bypass.

Tests: `tests/unit/bump-and-log.test.ts`.

### Crash reporter & auto-updater
`crashReporter.start({ submitURL: '', uploadToServer: false, …})` in
`src/main/index.ts` — minidumps stay on disk under
`<userData>/CrashReports/`.

`electron-updater` is wired to the GitHub release feed declared under
`build.publish` in `package.json`. Opt out with
`PURPLE_PDF_DISABLE_AUTO_UPDATE=1`.

## Known Limitations (1.0.0)

These are pre-existing data-model limitations; they're documented here
so the trade-off is explicit and post-1.0 candidates have somewhere to
start from.

1. **Annotations are keyed by original page index.** Adding an
   annotation to a *duplicate* slot also displays it on the original
   page on save, because `flatten.ts` looks up `annotsByPageIndex[idx]`
   where `idx` is the source page index. Fix candidate: switch to
   slot-keyed annotations (`annotsBySlotId[]`) and remap during save.

2. **Move ops identify by original page index.** Dragging a *duplicate*
   thumbnail records `{ op: 'move', page: <originalIdx> }`, so the
   first occurrence of that source moves instead. Fix candidate: same
   slot-id refactor.

Both are tracked in `docs/ROADMAP.md` under post-1.0.

## File Map (renderer)

```
src/renderer/src/
  App.tsx                       # top-level orchestrator; menu wiring; modals
  features/
    a11y/                       # AccessibilityCheckerPanel + rules
    annotate/                   # tools/, AnnotationLayer.tsx, flatten.ts
    forms/                      # AcroForm filling + recognition + JS sandbox
    ocr/                        # OCR panel + offline Tesseract runner
    pages/                      # Thumbnails sidebar (drag-reorder)
    properties/                 # Document Properties modal
    security/                   # Password modal, redaction overlay
    sign/                       # Signature pad + placement
    text/                       # unicodeFont.ts, watermark.ts, headerFooter.ts
    viewer/                     # PageCanvas, PDFViewer, projectOrder
    welcome/                    # empty-state screen
```

## File Map (main)

```
src/main/
  index.ts                      # menus, IPC, lifecycle
  assets.ts                     # pp-asset:// protocol
  print/                        # virtual-printer install scripts
  cli/                          # gs / qpdf / soffice wrappers (probe + run)
  capture/                      # screen capture + screen-to-PDF
  updates.ts                    # electron-updater wiring
  crash.ts                      # crashReporter init + folder reveal
```

## Where Data Lives

See [USER_MANUAL.md §17](USER_MANUAL.md#17-files--folders).

## Build & Release

`electron-builder` is configured for:
- macOS: `dmg` + `zip`, target `universal`, hardened runtime, notarize
  via `scripts/notarize.cjs`.
- Windows: `nsis` x64.
- `extraResources`: copies `resources/` (fonts + tesseract) into the
  packaged `Contents/Resources/resources/` so the app is fully
  self-contained.
