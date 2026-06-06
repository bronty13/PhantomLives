# PurpleMark — HANDOFF

Canonical architecture + status snapshot. Read this before non-trivial changes.
PurpleMark is a native macOS Markdown editor modeled on OpenMark: the system
default `.md` editor + Finder Quick Look previewer, with a single-pane
Document⇄Markdown toggle, bundled-offline Mermaid/LaTeX, tabs, find/replace,
custom themes, and Sparkle auto-update.

- **Stack:** Swift / SwiftUI, macOS 14+, **XcodeGen** (`project.yml`).
- **Current version:** git-derived `1.0.<commit-count>` (stamped into the built
  bundle by `build-app.sh`; tracked plists carry `0.0.0` placeholders).
- **Status:** v1 complete. Only the **iOS reader** remains on the roadmap.

## Targets (`project.yml` → 5)

| Target | Type | Role |
|---|---|---|
| `PurpleMark` | application | The SwiftUI editor app. |
| `PurpleMarkRenderCore` | framework | Markdown→HTML pipeline + bundled JS/CSS/fonts + the `ThemeColors` model + the Finder thumbnail renderer. Shared by the app **and** both extensions so rendering is byte-identical. |
| `PurpleMarkQuickLook` | app-extension | `QLPreviewProvider` — Finder spacebar preview. |
| `PurpleMarkThumbnail` | app-extension | `QLThumbnailProvider` — content-aware `.md` Finder icon. |
| `PurpleMarkTests` | unit-test | XCTest (~33 tests). |

Sparkle 2 is a SwiftPM package dep of the app; Xcode embeds `Sparkle.framework`
and `build-app.sh` re-signs its nested XPCServices/Updater/Autoupdate inside-out.

## How rendering works (the core idea)

Hybrid native-shell + bundled-JS (like OpenMark/MarkEdit). `RenderCore/Web/`
holds `index.html` + `styles.css` + vendored **offline** `markdown-it`,
`mermaid`, and `katex` (woff2 fonts base64-inlined for export/QL). The page
exposes `window.PM = { render, setWidth, setThemeVars, setTheme }`.

- **Live in-app Document view** (`MarkdownWebView`, NSViewRepresentable): loads
  `index.html` once via `loadFileURL`, then pushes markdown/theme/width changes
  through `evaluateJavaScript` (libraries parse once; re-renders are cheap).
- **Export + Quick Look** (`RenderCore.standaloneHTML`): builds one
  self-contained HTML string (everything inlined) — used for HTML export, PDF
  export (offscreen `WKWebView.createPDF`), and the QL preview extension.
- **Theming** is unified through `ThemeColors` (9 colors + `isDark`) applied as
  inline CSS variables via `PM.setThemeVars`. Built-in themes
  (`ThemeColors.builtin(_:)`) and custom themes share this one path.

## File map

```
Sources/PurpleMark/
  App/        PurpleMarkApp.swift (Window scene + Commands), AppDelegate.swift
              (open files → tabs, launch backup, first-run default prompt),
              Commands.swift (EditorAction bus + ExportCommands), Info.plist
              (CFBundleDocumentTypes/LSHandlerRank, UTImportedTypeDeclarations,
              Sparkle SUFeedURL/SUPublicEDKey), PurpleMark.entitlements
  Models/     Document.swift (per-tab state), AppState.swift (tab list + active
              + sidebar/find/folder), AppSettings.swift (@Stored UserDefaults
              wrapper), ThemeStore.swift (built-in+custom themes, persisted),
              FindController.swift (matching + command bus)
  Views/      ContentView.swift (TabBar + DocumentWindow + toolbar + EditorPane),
              TabBar, SourceTextView (NSTextView: highlight, ruler, format,
              find, focus/typewriter), LineNumberRuler, SidebarView
              (Outline|Files), StatusBar, FindReplaceBar, SettingsView,
              ThemeEditor (color pickers + live preview + Color⇄hex)
  Services/   FileService, ExportService, BackupService, DefaultHandlerService,
              OutlineParser, UpdaterController (Sparkle)
Sources/PurpleMarkRenderCore/  RenderCore, MarkdownWebView, ThemeColors,
              MarkdownThumbnail, Web/{index.html, styles.css, vendor/…}
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
