# Purple PDF — User Manual

A guided tour of every menu, panel, and shortcut in **Purple PDF 1.0.0**.

> Most shortcuts use **⌘** on macOS and **Ctrl** on Windows. The manual
> uses **⌘** throughout — substitute as needed.

## 1. The Window

```
┌───────────────────────────────────────────────────────────────┐
│ tab bar:  [file-1.pdf] [file-2.pdf]  [+]                       │
├───────┬──────────────────────────────────────┬────────────────┤
│ left  │                                      │ right side panel│
│ side  │           main viewer                │ (properties,    │
│ panel │                                      │  a11y checker,  │
│       │                                      │  ocr, …)        │
├───────┴──────────────────────────────────────┴────────────────┤
│ status bar:  page 3 / 12 · 125% · ⓘ messages                  │
└───────────────────────────────────────────────────────────────┘
```

- **Tab bar** — open multiple PDFs; close with the **×** button or ⌘W.
- **Left sidebar** — toggle Outline / Thumbnails / Find with the toolbar
  buttons or `F4`.
- **Main viewer** — pdf.js render. Scroll, pinch-zoom, ⌘+/⌘-.
- **Right sidebar** — context-specific. Auto-opens for OCR, Accessibility
  Checker, Document Properties, and Compare PDFs.

## 2. Opening & Recents

- **File → Open…** (`⌘O`) — pick any local file.
- **File → Open Recent** — last 10 documents, persisted via
  `electron-store` at `<userData>/recents.json`.
- **Drag-and-drop** a PDF anywhere on the window.
- **Print to Purple PDF** — from any app, choose the virtual printer
  installed by **File → Install "Print to Purple PDF"…**

## 3. Saving

- **File → Save** (`⌘S`) — overwrites the source file, flattening any
  pending annotations, signatures, and page operations.
- **File → Save As…** (`⇧⌘S`) — pick a new path.
- **Autosave** — every 5s of idle the document state is serialized to
  `<userData>/autosaves/<sha1>.json`. On startup, if a crash was detected,
  Purple PDF offers to recover.

## 4. Navigation

| Action | Shortcut |
| --- | --- |
| Next / Prev page | `→ / ←`, `PgDn / PgUp`, `Space / ⇧Space` |
| Go to page… | `⌘G` |
| Zoom in / out | `⌘+` / `⌘-` |
| Fit width / page | `⌘1` / `⌘0` |
| Find in page | `⌘F`, next: `⌘G`, prev: `⇧⌘G` |
| Outline panel | toolbar **Outline** button |
| Thumbnails panel | toolbar **Pages** button (drag to reorder) |

## 5. Annotate

Pick a tool in the **Annotate** menu. Drag on the page to apply.

- Highlight / Underline / Strikeout — operate on the **selected text**.
- Free Text — click to place a text box; double-click to edit.
- Pencil — freehand stroke; size and colour via the right-click context
  menu.
- Rectangle / Ellipse / Line / Arrow — drag to size.
- Sticky Note — click to drop; double-click to edit body.
- **Redact (certified)** — drag a rectangle; on **Save**, the visible
  blackout **and** the underlying glyphs/images are removed (`pdf-lib`
  + custom redaction). Metadata can be stripped at the same time via
  **File → Save As…** options.
- **Stamp (✪ / `M`)** — drop a business-style rubber stamp (APPROVED,
  DENIED, REVIEWED, RECEIVED, DRAFT, FINAL, CONFIDENTIAL, VOID, REVISED,
  ✓, ✗ — or any **custom stamp** you've defined in Preferences). Optional
  **Include date/time** and **Include user** lines render an italic
  subtitle (e.g. `By Robert Olen at 6:36 pm, May 21, 2026`).
- **Insert Image (🖼 / `I`)** — pick any PNG / JPEG / GIF / WebP / SVG /
  HEIC file from disk. Decoded in the renderer (no native deps; HEIC
  decoded via `heic2any`), placed at native aspect ratio, and embedded
  into the saved PDF as a real image XObject via `pdf-lib`.
- **Undo / Redo** — `⌘Z` / `⇧⌘Z`. Stack is per-tab.
- **Drag-to-move** + **8-handle resize** for any selected annotation
  (corners + edge midpoints; corners support flipping; min 4 pt).

Annotation size, colour, and opacity are exposed in the **Properties**
right-sidebar.

## 6. Edit Pages

Open the **Pages** sidebar. Each thumbnail supports:

- **Drag-to-reorder** (with drop indicator); reflected immediately in the
  main viewer.
- **Right-click → Rotate** 90° CW / 90° CCW / 180°.
- **Right-click → Delete**.
- **Right-click → Duplicate**.
- **Right-click → Insert Blank Page Before / After**.

All of these enqueue **page ops** that render in-canvas **previewed**
before save. The status bar shows e.g. *"12 pages → 14 pages (5 pending
ops)"*. Hit `⌘S` to flatten.

### Crop

- **Page → Crop…** — drag a rectangle on the page; the dimmed area is
  trimmed on save.
- **Page → Auto-Crop Margins** — pixel-scan via canvas to remove white
  borders.

## 7. Forms

- **Forms → Fill** — interactive AcroForm filling.
- **Forms → Recognize Fields** — heuristics on a flat document.
- **Forms → JavaScript Hooks** — sandboxed `calculate`, `validate`,
  `format` callbacks.
- **Forms → Export Data** — FDF / XFDF / JSON / CSV.

## 8. Sign

- **Sign → Draw / Type / Image…** — create a signature.
- Drag, resize, and place; on **Save** it's flattened to the page.
- **Sign → Certificate-based Signature…** — uses an OS-level cert (P12
  picker on Windows; Keychain on macOS).

## 9. Security

- **Security → Password Protect…** — AES-256 via qpdf, with per-permission
  toggles (print / copy / modify / annotate / fill forms).
- **Security → Remove Password…** — given the current owner password.
- **Security → Strip Metadata** — also available as a Save-As checkbox.
- **Certified Redaction** — see §5.

## 10. Watermark · Header / Footer · Bates

- **Page → Watermark…** — diagonal, semi-transparent text. Unicode-safe
  thanks to the bundled Noto Sans.
- **Page → Header / Footer / Bates…** — left / centre / right slots in
  the header and footer; tokens supported: `{page}`, `{total}`, `{date}`,
  `{bates}` (zero-padded auto-increment).

## 11. Compare PDFs

- **File → Compare PDFs…** — pick a second file. The modal shows two
  synchronized viewers with a difference colour wash.

## 12. Optimize

- **File → Optimize PDF…** — Ghostscript pre-set:
  `/screen` (smallest), `/ebook`, `/printer`, `/prepress`.

## 13. OCR (offline)

- **Tools → OCR Page** / **OCR Document** — runs Tesseract entirely
  on-device. The recognized text becomes an **invisible** layer in the
  PDF so copy-paste and find-in-page work.
- Bundled language: **English**. The worker, wasm, and traineddata are
  served via the internal `pp-asset://` protocol — no network access.

## 14. Standards

- **File → Convert to Standard → PDF/A-1b / PDF/A-2b / PDF/A-3b / PDF/X-3**
  — via Ghostscript.
- **View → Accessibility Checker** — pass / warn / fail / info severities.
- **File → Properties** (`⌘I`) — Title / Author / Subject / Keywords /
  Language. Saved to info dict and catalog `/Lang`.

## 14b. Preferences (`⌘,`)

**Edit → Preferences** (macOS) / **Edit → Settings** (Windows) opens
the Preferences window.

- **Stamps tab**
  - **Hide / show built-in stamps** — built-ins are immutable so future
    updates can't collide with your customizations; toggle visibility
    individually.
  - **Custom text stamps** — create / edit / delete / reorder. Each
    has: label, style (box / mark), color, default size, default
    subtitle.
  - **Custom image stamps** — for company logos or scanned rubber
    stamps; uses the same image pipeline as Insert Image. Tick
    **"Overlay user + date/time subtitle when placing"** to freeze a
    `By {you} at {time, date}` caption onto a translucent band along the
    image's bottom edge each time you stamp it (mirrors the text-stamp
    subtitle; the timestamp is frozen at placement).
  - **Import / export** as `.purplestamps.json` (text-only) or
    `.purplestamps` (ZIP bundle, image-aware). On import you'll be
    asked how to resolve conflicts (replace or rename).

Preferences are stored at `<userData>/purple-pdf-prefs.json` via
`electron-store`. Wipe the file to reset.

## 15. Crash Recovery & Auto-Update

- **Help → Show Crash Reports Folder** — opens
  `<userData>/CrashReports/`.
- **Help → Check for Updates…** — `electron-updater` over the GitHub
  release feed. Updates download in the background and install on next
  quit.

## 16. Keyboard Shortcuts (`⌘/`)

A complete cheat sheet is available from **Help → Keyboard Shortcuts**.

## 17. Files & Folders

User data is stored under Electron's `app.getPath('userData')`:

| Subpath | Contents |
| --- | --- |
| `recents.json` | Recent documents |
| `Captures/` | Screen-capture exports |
| `autosaves/<sha1>.json` | Crash-recovery snapshots |
| `purple-pdf-prefs.json` | Preferences (stamp library, UI toggles) |
| `CrashReports/` | Minidumps |
| `prefs.json` | Per-user preferences |

## 18. Privacy

Purple PDF makes **no network requests at runtime** for any shipped
feature. The single exception is the optional auto-update check against
the GitHub release feed, which can be disabled with
`PURPLE_PDF_DISABLE_AUTO_UPDATE=1`. Crash reports stay local unless you
explicitly attach them to an issue.
