# PurpleMark

A fast, native macOS Markdown editor — and the system **default editor** and
**Finder Quick Look previewer** for `.md` files. Modeled on
[OpenMark](https://openmarkapp.com/): a single clean pane that toggles between a
beautifully **rendered Document** view and a **syntax-highlighted Markdown**
source view, with inline **Mermaid** diagrams and **LaTeX** math — all bundled
and fully offline.

Part of the PhantomLives monorepo; one of the `Purple*` SwiftUI apps.

## Highlights

- **Single-pane toggle** — eye = rendered Document, `</>` = Markdown source.
- **Handles huge files** — a 100MB markdown file opens responsive: background
  load, viewport-only highlighting, and a chunked lazy preview (see *Large
  files* below).
- **Default `.md` handler + Quick Look** — double-click opens PurpleMark; press
  spacebar in Finder to preview rendered markdown (same renderer as the app).
- **Local images & relative links** render in the preview, served (and
  confined to) the document's folder; relative `.md` links open as tabs.
- **Sanitized by default** — raw HTML in markdown renders, but scripts and
  event handlers are stripped (bundled DOMPurify); external links open in
  your browser.
- **Drag-and-drop to open** — drag a `.md` file from Finder onto the window to
  open it in a tab. **Session restore** brings your tabs back on launch.
- **Mermaid + LaTeX**, bundled offline (no CDN, no network).
- **Outline | Files sidebar** — live TOC with exact heading jumps + a folder browser.
- **Export to PDF & HTML** and **Print (⌘P)**, preserving diagrams and math
  (→ `~/Downloads/PurpleMark/`).
- **Deep settings** — 4 themes + custom themes, reading widths, preview zoom,
  Focus / Typewriter / Zen modes, sync-scroll, accessibility fonts, and more.
- **Safe by default** — quit prompts for unsaved tabs; externally-changed
  files reload (or ask, if you have edits); auto-backup on launch of
  preferences + recent files.

## Architecture

Native **Swift / SwiftUI**, macOS 14+, built with **XcodeGen**. Five targets:

| Target | Role |
|---|---|
| `PurpleMark` | The SwiftUI editor app. |
| `PurpleMarkRenderCore` | Framework: the markdown→HTML pipeline + bundled JS/CSS/fonts, plus the Finder thumbnail renderer. Shared by the app and both extensions so output is consistent. |
| `PurpleMarkQuickLook` | `QLPreviewProvider` app-extension (Finder spacebar preview). |
| `PurpleMarkThumbnail` | `QLThumbnailProvider` app-extension (content-aware Finder icon for `.md`). |
| `PurpleMarkTests` | XCTest unit tests. |

Rendering is a hybrid native-shell + bundled-JS approach (like OpenMark /
MarkEdit): a `WKWebView` loads a bundled HTML template plus vendored
`markdown-it`, `dompurify`, `mermaid`, and `katex` (with its woff2 fonts
base64-inlined for export/Quick Look).

## Large files

PurpleMark is built to stay smooth at 100MB:

- Files load asynchronously (progress overlay) with encoding detection
  (UTF-8 → UTF-16 → Latin-1).
- The editor owns one `NSTextStorage` per document — keystrokes never copy the
  text; whole-document scans (outline, stats, fences, line offsets) run in a
  single debounced background pass; syntax highlighting covers only the
  viewport.
- The preview pulls the document as ~64KB chunks over a custom `pm-app://`
  scheme and re-renders only chunks whose hash changed; KaTeX/Mermaid render
  lazily as chunks approach the viewport.
- Past **10MB** a "Large file" mode pauses spellcheck, smart typography, and
  focus/typewriter modes (status-bar capsule explains). Past **48MB** the
  preview shows the leading portion with a "Render anyway" banner.
- Test fixture generator: `./Scripts/make-bigfile.sh 100` → `/tmp/pm-bigfile-100mb.md`.

## Security model

Markdown files are untrusted input (PurpleMark is the default `.md` handler).
Rendered HTML is sanitized with bundled DOMPurify — scripts, event handlers,
and `javascript:` URLs never run; Mermaid runs `securityLevel: strict`;
external links open in the default browser; doc-relative resources are
path-confined to the document's folder; Quick Look always sanitizes and caps
input at 2MB. Power users can opt into raw HTML via Settings → Editor →
"Allow raw HTML scripts in preview" (applies to the in-app preview and
exports, never Quick Look).

## Build / Run

```sh
./build-app.sh        # build + install to /Applications + relaunch (default)
./build-app.sh --no-open      # build + install, no focus steal
./build-app.sh --no-install   # build only
./run-tests.sh        # XCTest suite
```

`build-app.sh` regenerates the Xcode project from `project.yml`, builds, stamps
the git-derived version (`1.1.<commit-count>`) into the bundle, signs
(Developer ID if available, else ad-hoc), and chains into `install.sh` (which
force-kills any running copy, replaces `/Applications/PurpleMark.app`, relaunches,
and proves freshness).

> Requires full Xcode (not just Command Line Tools) — `build-app.sh` auto-selects
> `/Applications/Xcode.app` if `xcode-select` points at CLT.

## Set as default / Quick Look / thumbnails

On first launch PurpleMark offers to become your default Markdown editor; you can
also set it anytime via **Settings → Default Application → “Set as Default for
.md”**. Finder **Quick Look** (spacebar) and **thumbnails** work as soon as
PurpleMark has been launched once from `/Applications/` (Launch Services registers
the bundled extensions).

Debug registration:
```sh
pluginkit -m -p com.apple.quicklook.preview   | grep -i purplemark
pluginkit -m -p com.apple.quicklook.thumbnail | grep -i purplemark
qlmanage -t -s 512 -o /tmp SomeFile.md        # force-render a thumbnail
```

## Spotlight

`.md` contents are searchable in Spotlight because PurpleMark declares the
markdown UTI as conforming to `public.plain-text`, so macOS's built-in importer
indexes them (`mdfind <word-in-a-file>` finds it). A custom `.mdimporter` was
tried (1.0.6) and removed (1.0.7): on current macOS the system importer wins the
live index for markdown, so a third-party importer is inert here.

## Default output location

Exports default to `~/Downloads/PurpleMark/`; backups to
`~/Downloads/PurpleMark backup/`. Both are overridable in Settings. Caches/prefs
live under `~/Library/Application Support/PurpleMark/`.
