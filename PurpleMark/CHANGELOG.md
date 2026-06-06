# Changelog

All notable changes to PurpleMark are documented here.

## [1.0.3] - 2026-06-05

### Added
- **Find & Replace** in the Markdown source view — a find/replace bar (⌘F /
  ⌘⌥F) with literal or **regex** matching, a case-sensitivity toggle, a live
  "N of M" match count, next/previous (⌘G / ⇧⌘G) with the standard find
  indicator, and Replace / Replace All. Matching logic is pure and unit-tested.

## [1.0.2] - 2026-06-05

### Added
- **In-app auto-updates via Sparkle 2** — a "Check for Updates…" menu item and a
  Settings → Updates section (auto-check toggle, check-now, last-checked). The
  appcast is served from `PurpleMark/appcast.xml` via raw.githubusercontent; the
  public EdDSA key is the shared Purple\* key.
- **Notarized release process** — `Scripts/release.sh` builds a Developer-ID
  signed/hardened app (Sparkle's XPCServices/Updater/Autoupdate signed
  inside-out), packages a **notarized + stapled DMG**, EdDSA-signs it, creates the
  GitHub release, and updates the appcast. `RELEASING.md` documents the one-time
  per-Mac setup (shared `PurpleDedup-Notary` profile + shared Sparkle key).

## [1.0.1] - 2026-06-05

### Added
- **Finder thumbnails** for `.md` files — a new `PurpleMarkThumbnail`
  `QLThumbnailProvider` app-extension draws a content-aware page preview (purple
  accent + the document's first lines) so markdown files get a recognizable icon
  instead of a generic one. Shared, testable renderer in
  `PurpleMarkRenderCore/MarkdownThumbnail`.
- **First-run prompt** offering to set PurpleMark as the default Markdown editor
  (shown once; either choice is remembered so it never nags).
- 4 unit tests for thumbnail preview-line extraction.

## [1.0.0] - 2026-06-05

Initial release — a native macOS Markdown editor, default `.md` handler, and
Finder Quick Look previewer, modeled on OpenMark.

### Added
- **Single-pane editor** with a Document (rendered) ⇄ Markdown (source) toggle.
- **Rendered Document view** via a bundled, fully offline pipeline
  (markdown-it + Mermaid + KaTeX) — GitHub-flavored markdown, inline Mermaid
  diagrams, and LaTeX math, no network required.
- **Syntax-highlighted source editor** with a line-number gutter, word wrap,
  tab width, auto-close brackets, continue-lists, and spell check.
- **Toolbar** matching OpenMark: sidebar toggle, eye/`</>` view switch, centered
  title, B/I/S, text-size/theme/width menu, list/quote/code/link, export menu.
- **Outline | Files sidebar** — a live table-of-contents with colored heading
  badges, plus a folder browser of `.md` files.
- **Status bar** — live word / character / line counts and reading time.
- **Set as the default Markdown editor** (Settings → Default Application) and a
  bundled **Quick Look preview extension** so Finder's spacebar renders `.md`
  identically to the Document view.
- **Export to PDF and HTML**, preserving Mermaid diagrams and math; defaults to
  `~/Downloads/PurpleMark/`.
- **Full settings surface**: 4 themes (Default / Nord / Solarized / One Dark),
  default view, reading width, editor contrast, font size & family (including
  accessibility fonts), sync-scroll, Focus mode, Typewriter mode, Zen mode.
- **Auto-backup on launch** of PurpleMark's own state (prefs + recent files) to
  `~/Downloads/PurpleMark backup/`, 14-day retention, 5-minute debounce, plus the
  Settings → Backup UI.
- `build-app.sh` / hardened `install.sh` / `run-tests.sh` per the PhantomLives
  standards; 14 unit tests.
