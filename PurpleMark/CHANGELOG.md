# Changelog

All notable changes to PurpleMark are documented here.

## [1.1.0] - 2026-06-12

### Performance — 100MB markdown files

A ground-up large-file overhaul. Opening a 100MB file used to hang the app;
it now opens responsive, settles at ~380MB RSS, and stays smooth while typing,
scrolling, and previewing.

- **Async open with encoding detection** — big files read + decode in the
  background behind a progress overlay; UTF-8 (BOM-aware) → UTF-16 → system
  detection → Latin-1 fallback replaces the silent UTF-8-only failure.
- **Zero per-keystroke O(n)** — documents are backed by an `NSTextStorage` the
  editor edits in place (no full-text copies through bindings); change
  tracking is a version counter; outline/stats/line-offsets/fence-ranges come
  from one debounced background scan (`DocumentIndex`); find is debounced,
  backgrounded, and capped at 50k matches ("N+"); autosave writes off-main
  (5s debounce past 10MB).
- **Viewport-only syntax highlighting** — large documents highlight the
  visible range ± one screenful; the catastrophic multiline fence regex is
  replaced by indexed fence ranges; the line-number ruler binary-searches
  line offsets instead of counting from zero per scroll frame.
- **Chunked preview over a custom `pm-app://` scheme** — the document travels
  as ~64KB chunks pulled on demand instead of a whole-document JSON literal
  through `evaluateJavaScript`; an edit re-renders only the chunks whose hash
  changed (viewport-first, `content-visibility: auto`); KaTeX/Mermaid render
  lazily per chunk. Past 48MB the preview truncates with a "Render anyway"
  banner; a crashed WebKit process now reloads itself instead of going blank.
- **Large-file mode (>10MB)** — spellcheck, smart typography, and
  focus/typewriter modes pause (status-bar "Large file" capsule explains);
  the outline sidebar caps at 4,000 rows (50k+ eager rows aborted SwiftUI).

### Security

- **Raw HTML in markdown is sanitized by default** (bundled DOMPurify 3.2.6):
  scripts, event handlers, and `javascript:` URLs are stripped in the
  preview, exports, and Quick Look; benign inline HTML still renders.
  Mermaid runs `securityLevel: strict`. Opt out per-machine via Settings →
  Editor → "Allow raw HTML scripts in preview" (Quick Look always sanitizes).
  Verified by a WKWebView integration test.
- **External links open in your browser** — clicking `http(s)`/`mailto` no
  longer navigates the preview away in-app.
- Quick Look caps input at 2MB (was: inlined the whole file, hanging Finder
  on huge documents) and gains a Latin-1 fallback.

### Added

- **Local images & relative links** — images referenced relatively in a
  document finally render (served from the document's folder, confined to
  it); clicking a relative `.md` link opens it in a tab.
- **Quit safety** — ⌘Q with unsaved changes now prompts Save/Discard/Cancel
  per dirty tab (previously changes were silently lost).
- **Session restore** — open tabs and the active tab persist across launches.
- **External-change watch** — clean documents reload when another app (git,
  another editor) rewrites the file; dirty ones ask Keep Mine / Reload.
- **Print** (⌘P) through the offline pipeline (Mermaid + KaTeX included).
- **Preview zoom** — ⌘= / ⌘− / ⌘0, persisted.
- **Exact outline jumps** — heading clicks land on the heading (caret placed
  in source view; element-precise in the rendered view).
- **Selection counts** in the status bar; **Clear Menu** in Open Recent;
  title-bar proxy icon (drag it, ⌘-click for the path).
- Real error alerts for open/save failures (was: a beep).

### Changed

- Dirty tracking is version-based: undoing back to the exact saved state
  still shows "Edited" (saves no longer keep a duplicate copy of the text).
- Each document now has its own undo stack (undo survives tab switches and
  can never land in another tab); replace-all on a >10MB document clears
  undo history instead of holding a giant undo buffer.
- Version base bumped to `1.1.<commit-count>`.

### Tests

- 66 tests (33 new): encoding detection, document index, chunker (fence
  safety, round-trip, hash stability), viewport highlighter, large-file
  policy, find cap, document versioning, and an end-to-end sanitization
  proof in a real WKWebView.

## [1.0.8] - 2026-06-08

### Added
- **Drag-and-drop to open** — drag a `.md` (or other markdown/text) file from
  Finder onto the PurpleMark window to open it in a tab. Works over the whole
  window: the chrome (sidebar/toolbar/status/tabs) via a SwiftUI `onDrop`, the
  Markdown source editor (a custom `EditorTextView` subclass opens the dropped
  file instead of inserting its path — filtering the text view's registered
  drag types didn't hold, as NSTextView re-registers them on each window move),
  and the rendered Document view (the `WKWebView` intercepts the file
  navigation a drop triggers). Dropping several
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
