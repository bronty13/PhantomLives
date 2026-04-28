# MacSearchReplace

A native macOS application for multi-file search and replace, inspired by
Funduc Software's *Search and Replace* for Windows. Personal-use build.

- **Stack:** SwiftUI + AppKit, Swift Package Manager, bundled `ripgrep`.
- **Distribution:** Locally built `.app` bundle, ad-hoc codesigned. Not for
  Mac App Store distribution; not notarized.

## Repo layout

```
MacSearchReplace/
├── Package.swift               # umbrella SPM package (lib + 2 executables)
├── Packages/SnRCore/           # core library (search, replace, archive, …)
├── Apps/MacSearchReplace/      # SwiftUI app target sources + Info.plist
├── Apps/snr-cli/               # `snr` command-line tool
├── Scripts/                    # build & vendoring helpers
└── Docs/                       # architecture, .snrscript format, regex
```

## Build

Prerequisites: Xcode 16+ command-line tools, macOS 14+.

```bash
# 1. Vendor a universal ripgrep binary into Apps/MacSearchReplace/Vendored/rg
./Scripts/fetch-ripgrep.sh

# 2. Build the SwiftPM products
swift build -c release

# 3. Wrap the GUI executable into a proper .app bundle (ad-hoc codesigned)
./Scripts/build-app.sh

# 4. Optional — install the CLI into /usr/local/bin
./Scripts/install-cli.sh
```

The resulting app lands at `build/MacSearchReplace.app`. Drag to
`/Applications` (or `~/Applications`). On first launch macOS may flag the
ad-hoc signature; clear the quarantine attribute if needed:

```bash
xattr -dr com.apple.quarantine build/MacSearchReplace.app
```

## Test

Tests are written with the **swift-testing** framework. Running them
requires **full Xcode** (not just Command Line Tools) because CLT ships
the `Testing.framework` interface but omits `lib_TestingInterop.dylib`.

```bash
# With Xcode installed:
swift test \
  -Xswiftc -F -Xswiftc /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
  -Xlinker -rpath -Xlinker /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
```

The project builds cleanly with CLT-only (`swift build`) — only test
execution requires Xcode.

## Documentation

- [Docs/architecture.md](Docs/architecture.md)
- [Docs/snrscript-format.md](Docs/snrscript-format.md)
- [Docs/regex-cheatsheet.md](Docs/regex-cheatsheet.md)

## Status

Phase 4 complete — feature parity with Funduc *Search and Replace*.
See the parity matrix above and [`CHANGELOG.md`](CHANGELOG.md) for details.

## Documentation

- [`Docs/INSTALL.md`](Docs/INSTALL.md) — build & install instructions
- [`Docs/USER_MANUAL.md`](Docs/USER_MANUAL.md) — full user guide
- [`Docs/HANDOFF.md`](Docs/HANDOFF.md) — engineering handoff & architecture
- [`Docs/TESTING.md`](Docs/TESTING.md) — test plan & smoke harness
- [`Docs/architecture.md`](Docs/architecture.md) — module diagrams
- [`Docs/snrscript-format.md`](Docs/snrscript-format.md) — `.snrscript` schema
- [`Docs/regex-cheatsheet.md`](Docs/regex-cheatsheet.md) — regex reference
- [`CHANGELOG.md`](CHANGELOG.md) — release notes
- [`LICENSE`](LICENSE) — MIT

## Funduc Parity Matrix

Comparison against Funduc *Search and Replace* / *Replace Studio Pro*. ✅ = supported, 🟡 = partial, ❌ = out of scope.

| Capability                                    | MacSearchReplace |
|-----------------------------------------------|:----------------:|
| Multi-file recursive search                   | ✅ |
| Literal / regex / multi-line / case / whole-word | ✅ |
| Include / exclude masks (multiple)            | ✅ |
| Date and size filters                         | ✅ |
| Honor `.gitignore`                            | ✅ |
| Encoding auto-detection (UTF-8/16, Latin-1, Shift-JIS) | ✅ |
| Streaming results, per-file outline           | ✅ |
| Highlighted match text + context preview      | ✅ |
| Stop-search button (Cmd-.)                    | ✅ |
| Replace with confirmation prompt (Y/N/All/Skip File) | ✅ |
| Multiple find/replace pairs in one pass       | ✅ |
| Atomic, crash-safe replace + APFS clonefile backups | ✅ |
| Undo / restore from backup session            | ✅ |
| Saved scripts (`.snrscript` v1 + v2 multi-step) | ✅ |
| Per-step roots / include / exclude overrides  | ✅ |
| Counter replacement `\#{start,step,format}`   | ✅ |
| Binary / hex mode (length-preserving)         | ✅ |
| Touch (set mtime/atime)                       | ✅ |
| Search inside ZIP                             | ✅ |
| Search inside OOXML (.docx/.xlsx/.pptx)       | 🟡 (rewrite path enabled; full round-trip fixtures pending) |
| Search inside TAR/TGZ                         | ✅ |
| Search PDF text (read-only)                   | ✅ |
| Drag results to Finder / external editor      | ✅ |
| Open in external editor (BBEdit / VS Code / Xcode) | ✅ |
| Export results (CSV / JSON / HTML / TXT)      | ✅ |
| Favorites / recent folders                    | ✅ |
| Preferences window                            | ✅ |
| Companion CLI (`snr`)                         | ✅ |
| Quick Look + Services menu                    | 🟡 (deferred) |
| HTML entity / Unicode lookup tables           | ❌ (Phase 5) |
| Boolean script gating expressions             | ❌ (Phase 5) |
| Inline edit in context viewer                 | ❌ (Phase 5) |
| Localization beyond English                   | ❌ |
| AppleScript dictionary                        | ❌ |
