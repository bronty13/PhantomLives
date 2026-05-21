# Purple PDF — Roadmap

## Released

| Version | Date | Theme |
| --- | --- | --- |
| 1.0.0 | 2026-05-20 | **GA.** Docs refresh, JSDoc, unit-test fill-in, cleanup. |
| 0.9.0 | 2026-05-20 | Drag-reorder, optimize, watermark, header/footer/bates, auto-crop, manual crop, compare, autosave, **offline** OCR, bundled Unicode font, in-canvas previews, auto-version hook. |
| 0.8.0 | 2026-05-20 | Auto-updater, crash reporter, help menu, hardened runtime, docs quintet. |
| 0.7.0 | — | Standards (PDF/A, PDF/X) + accessibility checker + Document Properties. |
| 0.6.0 | — | E-signatures + AES-256 + certified redaction. |
| 0.5.0 | — | Forms: fill, recognize, JS, export. |
| 0.4.0 | — | Create / convert: image, URL, scan, Office. |
| 0.3.0 | — | Virtual printer (mac CUPS + Windows port-monitor). |
| 0.2.0 | — | Annotate + page edits + undo. |
| 0.1.0 | — | Multi-tab viewer + sidebars + recents. |
| 0.0.1 | — | Scaffold + branding. |

## Post-1.0 — Candidate (no commitment)

### 1.1.0 — Data model polish
- **Slot-id annotations.** Refactor `flatten.ts` to key annotations by
  projected slot id instead of original page index — fixes the two
  known limitations called out in `DESIGN.md` (duplicates inherit
  annotations; move-by-duplicate confusion).
- Per-tool default colour / size persistence in `prefs.json`.

### 1.2.0 — Localization
- i18n scaffold via `react-i18next`.
- ship `en`, `es`, `pt`, `de`, `fr`, `ja` initially.
- Add **Tesseract** language packs as optional opt-in downloads (stored
  under `<userData>/tesseract-langs/`, side-loaded via the `pp-asset://`
  fallback search path).

### 1.3.0 — Collaboration
- Comment threads on annotations (reply / resolve).
- Annotation export / import as `.fdf` for round-tripping with
  other readers.

### 1.4.0 — Optional cloud sync (opt-in)
- WebDAV / iCloud Drive / OneDrive folder watcher.
- E-sign requests via mailto:// fallback (no server required).

### 2.0.0 — Architecture
- Replace the redaction overlay + flatten path with a true content
  stream rewrite for **provable** certified redaction.
- Plugin API for third-party tools.

## Out of Scope

- Telemetry / analytics — Purple PDF stays local-first.
- Required online accounts — every shipped feature works offline.
- Building our own PDF engine — we will keep composing `pdf.js` +
  `pdf-lib` + CLIs.
