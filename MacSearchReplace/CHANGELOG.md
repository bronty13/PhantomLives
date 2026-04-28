# Changelog

All notable changes to MacSearchReplace are documented here.
This project follows [Semantic Versioning](https://semver.org/) once it tags
a 1.0; pre-1.0 versions may break compatibility freely.

## [Unreleased] — Phase 4: Funduc parity

### Added
- `SnRPDF` module — PDFKit-based read-only PDF text search.
- `SnRArchive/TarRewriter` — round-trip search-and-replace inside `.tar`,
  `.tgz`, `.taz`, `.tar.gz`, and `.tar.Z` archives via `/usr/bin/tar`.
- `SnRReplace/FileTouch` — set mtime/atime on selected files.
- `SnRScript v2` — per-step `roots`, `include`, `exclude`, `honorGitignore`,
  `maxFileBytes` overrides; v1 scripts still load unchanged.
- Stop button (`⌘.`) cancels in-flight ripgrep searches cleanly.
- Filters disclosure: date and size filters; archive/PDF source toggles.
- Multiple S/R pairs sheet (single-pass multi-replace).
- Replace-with-prompt sheet (Yes/No/All/Skip-File ask-each mode).
- Drag-from-results to Finder, Mail, BBEdit, etc.
- Open-in-external-editor (auto-detects BBEdit, VS Code, Xcode).
- Export results to CSV, JSON, HTML, or plain text.
- Preferences window — General / Editors / Archives / Display / Performance.
- Open Recent Folder menu (last 10 roots).
- `snr touch` and `snr pdf` CLI subcommands.
- `Tests/smoke.sh` — 16 end-to-end CLI tests; gate for releases.
- Comprehensive docs: `INSTALL.md`, `USER_MANUAL.md`, `HANDOFF.md`,
  `CHANGELOG.md`, parity matrix in `README.md`.

### Changed
- `Searcher.ripgrepStream` now wires `continuation.onTermination` to
  terminate the spawned `rg` process when the consumer cancels.
- `SnRCore` re-exports `SnRPDF` so the UI/CLI can `import SnRCore` only.
- README expanded with the full Funduc parity matrix.

### Fixed
- `FileTouch.swift` warning about unused `var attrs` (changed to `let`).

## [0.1.0] — Phase 1–3: MVP

### Added
- SwiftUI app with Funduc-classic three-pane layout
  (criteria → outline → context preview).
- Match highlighting (yellow background, bold) and replacement preview
  (strike-through original, green replacement).
- Favorites — save and load named search criteria sets.
- Per-row context menu — Open / Reveal in Finder / Copy.
- Pressing Return in any criteria field runs Find.
- `snr` CLI: `search`, `replace`, `run`, `restore`.
- `SnRCore` library:
  - `SnRSearch` — ripgrep streaming + native enumerator fallback.
  - `SnRReplace` — atomic write via tmp+rename; counter expansion;
    path-token interpolation; binary length-preserving mode.
  - `SnREncoding` — auto-detect UTF-8/16/Latin-1/Shift-JIS.
  - `SnRArchive` — ZIP rewrite via `Compression` framework; OOXML detection.
  - `SnRScript` v1 — single-scope ordered pipeline.
- APFS clonefile-based backup sessions with `manifest.json`.
- Vendored ripgrep 14.1.1 (universal binary).
- Build scripts: `fetch-ripgrep.sh`, `build-app.sh`.
