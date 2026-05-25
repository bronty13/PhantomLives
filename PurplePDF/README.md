# Purple PDF

A full-featured, cross-platform PDF reader and editor for **macOS and Windows**. Local-first, no telemetry, no account required.

[![version](https://img.shields.io/badge/version-1.0.0-purple)]() [![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey)]() [![license](https://img.shields.io/badge/license-UNLICENSED-blue)]()

> **Status: 1.0.0 — General Availability.** All 10 development phases (P0–P10) shipped.
>
> **Location**: a subproject of [PhantomLives](https://github.com/bronty13/PhantomLives) — see the root `CLAUDE.md` for the monorepo's release-hygiene rules and the `install.sh` standard this app follows.

## What's in the box

- 📖 **Read** — multi-tab, multi-page, full pdf.js renderer with outline / thumbnails / find-in-page / accessibility tree.
- ✏️ **Annotate** — highlight, underline, strikeout, freehand, shapes, sticky notes, text boxes, redact (with underlying-content removal), business stamps (built-in + custom library), insert image (PNG/JPEG/GIF/WebP/SVG/HEIC).
- 📝 **Edit** — drag-to-reorder pages, delete / duplicate / insert-blank / rotate / crop / auto-crop with **live in-canvas preview**.
- 🖋️ **Sign** — draw, type, or image-based signatures; AES-256 password protection (qpdf); permission flags; certified redaction.
- 📰 **Forms** — fill, recognize fields from flat docs, sandboxed JS hooks, export FDF / XFDF / JSON / CSV.
- 🔁 **Create & Convert** — image-to-PDF, URL-to-PDF (headless Chromium), scan-to-PDF, bidirectional Office (LibreOffice), PDF/A & PDF/X (Ghostscript).
- 🖨️ **Print to Purple PDF** — virtual printer for macOS (CUPS) and Windows (port-monitor).
- 🔎 **OCR** — fully **offline** Tesseract (English) with bundled wasm + traineddata.
- 🌐 **Unicode-aware stamps** — Noto Sans bundled and used for watermark, header/footer/Bates, OCR text layer (no more dropped em-dashes or CJK).
- 💾 **Crash recovery** — debounced autosave with startup recovery prompt.
- ♻️ **Auto-update** — `electron-updater` over the GitHub release feed; opt-out friendly.
- ♿️ **Accessibility** — keyboard nav everywhere, visible focus rings, built-in checker, screen-reader-friendly text layer, `/Lang` on save.

See **[docs/USER_MANUAL.md](docs/USER_MANUAL.md)** for the full feature tour.

## Quick start

```sh
# 1. Install JS dependencies (first time only — build-app.sh also does
#    this on first run if node_modules is missing)
npm install

# 2. (Optional) install the auto-version pre-commit hook
bash scripts/install-git-hooks.sh

# 3. Dev (hot-reload main + preload + renderer)
npm run dev

# 4. Type-check + test
npm run typecheck
npm test

# 5. Build + install + relaunch /Applications/Purple PDF.app
#    (PhantomLives install.sh standard — see ../CLAUDE.md)
./build-app.sh                       # build + install + relaunch
./build-app.sh --no-open             # build + install, skip relaunch
./build-app.sh --no-install          # build only, leave under dist/
./install.sh                          # re-install last-built bundle

# 6. Signed/universal release artifacts
npm run dist:mac     # .dmg + .zip (universal2)
npm run dist:win     # .exe (NSIS)
```

End users should follow **[docs/INSTALL.md](docs/INSTALL.md)** instead.

## Stack

- **Electron 31** + TypeScript + React 18 + Vite via [`electron-vite`](https://electron-vite.org/)
- **Render**: `pdfjs-dist`
- **Edit / save**: `pdf-lib` (+ `@pdf-lib/fontkit` for Unicode TTFs)
- **OCR**: `tesseract.js` v7, **bundled offline** under `resources/tesseract/`
- **Office ↔ PDF**: LibreOffice CLI (graceful-degradation)
- **AES-256 + permissions**: `qpdf` CLI (graceful-degradation)
- **PDF/A & PDF/X & Optimize**: Ghostscript CLI (graceful-degradation)
- **Packaging**: `electron-builder` → `.dmg` (universal2) + `.exe` (NSIS)

## Layout

```
PurplePDF/
  build-app.sh            # PhantomLives convention — host-arch build + auto-install
  install.sh              # PhantomLives convention — reinstall to /Applications + relaunch
  build/                  # macOS .icns + Windows .ico + entitlements + icon generator
                          # (electron-builder buildResources, NOT shipped at runtime)
  resources/              # extraResources packaged into Contents/Resources/resources/:
    fonts/                #   Noto Sans Regular + Bold (bundled Unicode font)
    tesseract/            #   worker.min.js + wasm + eng.traineddata.gz
  src/
    main/                 # Electron main process (menus, IPC, CLI bridges)
    preload/              # contextBridge-exposed window.purplePDF API
    renderer/src/         # React + TS UI
      App.tsx
      features/           # annotate, viewer, forms, sign, security, ocr, …
  scripts/                # universal release build (build-app.sh / build-app.ps1),
                          # install-and-launch (legacy), install-pdf-service,
                          # install-git-hooks, bump-and-log, notarize
  tests/unit/             # vitest unit tests
  docs/                   # USER_MANUAL, DESIGN, INSTALL, ROADMAP, HANDOFF
  CHANGELOG.md            # canonical changelog (auto-updated per commit)
```

## Documentation

- **[docs/USER_MANUAL.md](docs/USER_MANUAL.md)** — every menu, panel, and shortcut.
- **[docs/INSTALL.md](docs/INSTALL.md)** — end-user install + optional CLI setup.
- **[docs/DESIGN.md](docs/DESIGN.md)** — architecture, engine strategy, data model.
- **[docs/HANDOFF.md](docs/HANDOFF.md)** — operator's guide for taking over the project.
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — what shipped when; what's next.
- **[CHANGELOG.md](CHANGELOG.md)** — release notes (auto-maintained).

## License

UNLICENSED — private project. See `package.json`.
