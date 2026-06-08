# Changelog

All notable changes to PurpleMark are documented here.

## [1.0.8] - 2026-06-08

### Added
- **Drag-and-drop to open** — drag a `.md` (or other markdown/text) file from
  Finder onto the PurpleMark window to open it in a tab. Works over the whole
  window: the chrome (sidebar/toolbar/status/tabs) via a SwiftUI `onDrop`, the
  Markdown source editor (the `NSTextView` now lets file drops fall through
  instead of inserting the path), and the rendered Document view (the
  `WKWebView` intercepts the file navigation a drop triggers). Dropping several
  files opens each (the last becomes active); directories and unsupported file
  types are ignored. Complements the existing double-click / drop-on-app-icon
  paths, reusing the same `AppState.open(_:)` logic (already-open files just
  focus their tab).

## [1.0.7] - 2026-06-05

### Removed
- The bundled Spotlight `.mdimporter` (added in 1.0.6). After registration was
  verified post-reboot, testing confirmed it's **inert on current macOS**: the
  system `RichText` importer wins the live index for markdown (via
  `public.plain-text` conformance), so our importer's heading-title and "Markdown
  Document" kind never reach the index, even though `mdimport -t` selects it.
  **Spotlight content search still works** — macOS indexes `.md` contents because
  PurpleMark declares the markdown UTI as conforming to `public.plain-text`
  (verified with `mdfind` finding a file by an in-body token). Removed the dead
  target rather than ship a Spotlight extension that has no effect.

## [1.0.6] - 2026-06-05

### Added
- **Spotlight content importer** — a bundled `.mdimporter` CFPlugin
  (`Contents/Library/Spotlight/PurpleMark.mdimporter`) that indexes a markdown
  file's text content plus its first heading as the title and a "Markdown
  Document" kind, so Spotlight can find `.md` files by their contents and show a
  proper title. It claims the specific `net.daringfireball.markdown` type.
  - Note: macOS already indexes `.md` *contents* via its built-in plain-text
    importer (because PurpleMark declares markdown as conforming to
    `public.plain-text`), so content search works regardless; this importer adds
    the markdown-specific title/kind metadata where it's the registered handler.

### Fixed
- Test target compiled against a removed `AppSettings.theme` accessor (a 1.0.5
  cleanup slip) — updated to use `themeRaw`. Tests build green again (33/33).

## [1.0.5] - 2026-06-05

### Added
- **Custom theme editor** — create your own Document-view themes. Settings →
  Appearance now shows all themes (the four built-ins + your custom ones) as
  selectable swatches, with **New Custom Theme…**, **Edit…**, and **Delete**. The
  editor has color pickers for all nine theme colors (background, text, muted,
  links, rules, code/pre backgrounds, table stripe), a dark/light toggle (which
  also sets the Mermaid diagram theme), and a live preview. Custom themes persist
  to `~/Library/Application Support/PurpleMark/themes.json` and apply everywhere
  the built-ins do (Document view + PDF/HTML export).

### Changed
- Theming is now unified through a `ThemeColors` model applied as inline CSS
  variables (`PM.setThemeVars`), so built-in and custom themes share one render
  path. `RenderCore.standaloneHTML` and `MarkdownWebView` take `ThemeColors`.

## [1.0.4] - 2026-06-05

### Added
- **Multiple documents in tabs** — open several `.md` files at once in a single
  window. A tab strip appears when more than one document is open, with a `+` to
  add tabs, per-tab dirty indicators, and a close `×`. **⌘T** new tab, **⌘W**
  close tab; opening an already-open file focuses its tab. Each tab keeps its own
  text, file, view mode, and scroll position.

### Changed
- The app now uses a single `Window` scene (not `WindowGroup`) — documents live
  in in-app tabs, so the app no longer spawns extra OS windows for new/opened
  files. Per-document state moved into a new `Document` model.

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
