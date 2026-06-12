# PurpleMark — HANDOFF

Canonical architecture + status snapshot. Read this before non-trivial changes.
PurpleMark is a native macOS Markdown editor modeled on OpenMark: the system
default `.md` editor + Finder Quick Look previewer, with a single-pane
Document⇄Markdown toggle, bundled-offline Mermaid/LaTeX, tabs, find/replace,
custom themes, and Sparkle auto-update.

- **Stack:** Swift / SwiftUI, macOS 14+, **XcodeGen** (`project.yml`).
- **Current version:** git-derived `1.1.<commit-count>` (stamped into the built
  bundle by `build-app.sh`; tracked plists carry `0.0.0` placeholders).
- **Status:** v1.1 — large-file (100MB) overhaul + sanitized rendering complete
  (see CHANGELOG 1.1.0). Only the **iOS reader** remains on the roadmap.

## Targets (`project.yml` → 5)

| Target | Type | Role |
|---|---|---|
| `PurpleMark` | application | The SwiftUI editor app. |
| `PurpleMarkRenderCore` | framework | Markdown→HTML pipeline + bundled JS/CSS/fonts + the `ThemeColors` model + the Finder thumbnail renderer. Shared by the app **and** both extensions so rendering is byte-identical. |
| `PurpleMarkQuickLook` | app-extension | `QLPreviewProvider` — Finder spacebar preview. |
| `PurpleMarkThumbnail` | app-extension | `QLThumbnailProvider` — content-aware `.md` Finder icon. |
| `PurpleMarkTests` | unit-test | XCTest (66 tests, incl. a WKWebView sanitization integration test). |

Sparkle 2 is a SwiftPM package dep of the app; Xcode embeds `Sparkle.framework`
and `build-app.sh` re-signs its nested XPCServices/Updater/Autoupdate inside-out.

## How rendering works (the core idea)

Hybrid native-shell + bundled-JS (like OpenMark/MarkEdit). `RenderCore/Web/`
holds `index.html` + `styles.css` + vendored **offline** `markdown-it`,
`dompurify`, `mermaid`, and `katex` (woff2 fonts base64-inlined for export/QL).
The page exposes `window.PM = { render, refresh, scrollToHeading, setWidth,
setThemeVars, setTheme }`.

- **Live in-app Document view** (`MarkdownWebView`, NSViewRepresentable): loads
  the page over a custom **`pm-app://` scheme** (`PreviewSchemeHandler`), which
  serves bundled assets, a chunk **manifest** (`{version, hashes}`), individual
  ~64KB markdown **chunks** (`MarkdownChunker` — blank-line boundaries, never
  inside fences, FNV-1a hashes, ref-def hoisting), and **`pm-app://doc/<path>`**
  for resources next to the open document (local images; path-confined). A
  render push is one tiny `PM.refresh(version)`; the page diffs hashes and
  re-renders only changed chunks (viewport-first, `content-visibility:auto`,
  KaTeX/Mermaid via IntersectionObserver). Past the 48MB cap the preview
  truncates with a "Render anyway" banner. Web-process termination reloads
  + replays state.
- **Sanitization:** every render path routes through DOMPurify unless
  `Options.allowRawHTML` (Settings opt-in); Mermaid `strict` by default;
  external links open in the browser via the navigation policy.
- **Export + Quick Look** (`RenderCore.standaloneHTML`): builds one
  self-contained HTML string (everything inlined) — used for HTML export, PDF
  export (offscreen `WKWebView.createPDF`), Print (`printOperation`), and the
  QL preview extension (2MB cap, always sanitized). It textually extracts the
  page's single IIFE (`appScript()`) — **the index.html JS must stay one
  `(function () { … })();` block.**
- **Theming** is unified through `ThemeColors` (9 colors + `isDark`) applied as
  inline CSS variables via `PM.setThemeVars`. Built-in themes
  (`ThemeColors.builtin(_:)`) and custom themes share this one path.

## Large-file architecture (the 1.1.0 overhaul)

A 100MB file must never hang the main thread. The invariants:

- **`Document` owns an `NSTextStorage`**; `SourceTextView` attaches its layout
  manager to it (`replaceTextStorage`, non-contiguous layout). A keystroke
  edits in place and calls `doc.noteEdited()` — never copy `text` per edit.
  `Document.text` materializes lazily (save, preview push, find, index).
- **Change tracking is `textVersion`** (Int). Never compare document strings;
  dirty = `textVersion != savedVersion` (so undo-to-saved still shows Edited).
- **`DocumentIndex`** (one debounced background pass) provides outline, stats,
  `lineStartOffsets`, and fence ranges. Consumers: sidebar, status bar,
  `LineNumberRuler` (binary search, not count-from-zero), the viewport
  highlighter's fence coloring, and outline line-jumps.
- **Highlighting is viewport-only** past 300k UTF-16 units (`highlightRange`),
  re-run on an 80ms scroll debounce; the multiline fence regex is **gone** —
  don't reintroduce whole-document regex passes.
- **`LargeFilePolicy`** (pure) maps byteSize → feature flags: >10MB pauses
  spellcheck/typography/focus modes and stretches debounces; >48MB caps the
  preview. Status bar shows the "Large file" capsule.
- SwiftUI hazard: never `ForEach` an unbounded document-derived list eagerly —
  the outline sidebar is a `LazyVStack` capped at 4,000 rows because 50k+ rows
  abort in AttributeGraph (found with the 100MB fixture).
- Fixture: `./Scripts/make-bigfile.sh 100`.

## File map

```
Sources/PurpleMark/
  App/        PurpleMarkApp.swift (Window scene + Commands), AppDelegate.swift
              (open files → tabs, launch backup, first-run default prompt),
              Commands.swift (EditorAction bus + ExportCommands), Info.plist
              (CFBundleDocumentTypes/LSHandlerRank, UTImportedTypeDeclarations,
              Sparkle SUFeedURL/SUPublicEDKey), PurpleMark.entitlements
  Models/     Document.swift (per-tab state: NSTextStorage, versions, async
              load, file watch, per-doc UndoManager), AppState.swift (tab list
              + active + sidebar/find/folder + session persist/restore),
              AppSettings.swift (@Stored UserDefaults wrapper),
              LargeFilePolicy.swift (size→feature flags), ThemeStore.swift
              (built-in+custom themes, persisted), FindController.swift
              (matching + debounced recompute + command bus)
  Views/      ContentView.swift (TabBar + DocumentWindow + toolbar + EditorPane
              + loading/failed panes), TabBar, SourceTextView (NSTextView:
              viewport highlight, ruler, format, find, focus/typewriter,
              selection stats), LineNumberRuler, SidebarView (Outline|Files,
              LazyVStack + row cap), StatusBar, FindReplaceBar, SettingsView,
              ThemeEditor (color pickers + live preview + Color⇄hex)
  Services/   FileService, FileLoader (async read + encoding detection),
              DocumentIndex (one-pass scan), ExportService (HTML/PDF/Print),
              BackupService, DefaultHandlerService, OutlineParser (wrapper),
              UpdaterController (Sparkle)
Sources/PurpleMarkRenderCore/  RenderCore, MarkdownWebView, MarkdownChunker,
              PreviewSchemeHandler, ThemeColors, MarkdownThumbnail,
              Web/{index.html, styles.css, vendor/…}
Sources/PurpleMarkQuickLook/   PreviewProvider + Info.plist + entitlements
Sources/PurpleMarkThumbnail/   ThumbnailProvider + Info.plist + entitlements
Scripts/release.sh, Scripts/generate-icon.swift
```

## Build / test / release

```sh
./build-app.sh            # regen project → build → stamp version → sign
                          #   (Developer ID or ad-hoc) → install → relaunch →
                          #   freshness proof. --no-install / --no-open / BUILD_ONLY=1
./run-tests.sh            # XCTest via xcodebuild
./Scripts/release.sh      # Developer-ID build → DMG → notarytool staple →
                          #   Sparkle sign_update → gh release → appcast.xml
```

Requires full Xcode (build scripts auto-select `/Applications/Xcode.app` if
`xcode-select` points at CLT). Release credentials + per-Mac setup: `RELEASING.md`
(shared `PurpleDedup-Notary` profile + shared Sparkle key `2q4I3WNk7q…`).

## Key decisions & gotchas

- **`Window`, not `WindowGroup`.** Multi-document lives in in-app tabs; a
  `WindowGroup` + singleton `AppState` spawned extra OS windows per opened file.
  The single `Window` scene fixes that. (1.0.4)
- **Manual `HStack` sidebar, not `NavigationSplitView`** (house rule). `AppState`
  is a `@MainActor` singleton; views observe the active `Document`.
- **Sparkle signing order matters** — XPCServices `.xpc` → `Updater.app` →
  `Autoupdate` → `Sparkle.framework`, all before the app. `build-app.sh` does
  this; don't reorder. `SUPublicEDKey` is hardcoded in Info.plist (public, shared).
- **Default-handler is a manual click** (`NSWorkspace.setDefaultApplication`
  can't be invoked silently) — there's a once-only first-run prompt + a Settings
  button. Quick Look preview + thumbnail register via Launch Services once the app
  has run from `/Applications/`.
- **Spotlight (resolved, see CHANGELOG 1.0.6→1.0.7):** `.md` content search works
  for free (PurpleMark declares the markdown UTI as conforming to
  `public.plain-text`, so macOS indexes contents — `mdfind` proves it). A custom
  `.mdimporter` was built and **removed**: on current macOS the system RichText
  importer wins the live index for markdown, so a third-party importer is inert.
  Don't re-add one without new evidence that macOS stopped overriding it.
- **Dev-Mac registration flakiness:** heavy reinstall churn can wedge
  `pkd`/Launch Services so the Quick Look/thumbnail extensions stop registering
  (`pluginkit -m | grep purplemark` empty). A reboot clears it; this is a dev-loop
  artifact, not a bundle defect (deep `codesign --verify` passes).

## Deferred / next steps

- **iOS reader** (Universal Purchase companion, OpenMark-style) — the one
  remaining roadmap item. `RenderCore` is the natural shared piece, but the web
  assets + a read-only SwiftUI shell would need an iOS target.
- Possible polish: regex **replacement templates** (`$1`) in Find & Replace
  (currently literal); per-window `FindController` if a second window is ever
  added; richer "AA" font popover.
- Verify on the second Mac after a real `./Scripts/release.sh` run (notarization
  is the maintainer's credentialed step; not exercised in-session).
