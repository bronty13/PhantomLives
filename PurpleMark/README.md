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
- **Default `.md` handler + Quick Look** — double-click opens PurpleMark; press
  spacebar in Finder to preview rendered markdown (same renderer as the app).
- **Mermaid + LaTeX**, bundled offline (no CDN, no network).
- **Outline | Files sidebar** — live TOC + a folder browser.
- **Export to PDF & HTML**, preserving diagrams and math (→ `~/Downloads/PurpleMark/`).
- **Deep settings** — 4 themes, reading widths, Focus / Typewriter / Zen modes,
  sync-scroll, accessibility fonts, tab width, and more.
- **Auto-backup on launch** of preferences + recent files.

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
`markdown-it`, `mermaid`, and `katex` (with its woff2 fonts base64-inlined for
export/Quick Look).

## Build / Run

```sh
./build-app.sh        # build + install to /Applications + relaunch (default)
./build-app.sh --no-open      # build + install, no focus steal
./build-app.sh --no-install   # build only
./run-tests.sh        # XCTest suite
```

`build-app.sh` regenerates the Xcode project from `project.yml`, builds, stamps
the git-derived version (`1.0.<commit-count>`) into the bundle, signs
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

## Default output location

Exports default to `~/Downloads/PurpleMark/`; backups to
`~/Downloads/PurpleMark backup/`. Both are overridable in Settings. Caches/prefs
live under `~/Library/Application Support/PurpleMark/`.
