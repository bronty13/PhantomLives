# Changelog

All notable changes to MacSearchReplace are documented here.
This project follows [Semantic Versioning](https://semver.org/) once it tags
a 1.0; pre-1.0 versions may break compatibility freely.

## [Unreleased]

### Added — Funduc parity audit and roadmap (2026-04-28)
- `Docs/planning/sr_feature_catalog.md` — exhaustive feature inventory of
  Funduc Search and Replace for Windows, derived from the decompiled CHM
  help files at `~/Downloads/SR/`. 1,491 lines across 16 sections.
  Authoritative reference for the rebuild.
- `Docs/planning/codebase_assessment.md` — snapshot of the current Swift
  codebase as of 2026-04-27.
- `Docs/planning/parity_plan.md` — gap analysis against the catalog and a
  6-phase roadmap (engine → search modes → files & filters → UI rebuild →
  scripts & CLI → polish). Documents the seven load-bearing decisions
  (regex engine, UI shape, script format, CLI shape, replacement tokens,
  file operations, print) and the user's selections.
- `Docs/planning/phase_a_plan.md` — concrete Phase A implementation plan:
  new `SnRFunducRegex` and `SnRFunducReplace` modules, AST design, ICU
  translator strategy, custom evaluators for non-translatable operators
  (`!`, `+n`, `^^`, `$$`), test corpus from catalog examples, wiring
  approach, ~17-day estimate.

### Note
- The audit found that the prior "Phase 4 = Funduc parity" claim does not
  hold against the original help-file source of truth: regex syntax
  (PCRE vs Funduc's bespoke `*[0-9]`-style), replacement-token syntax
  (`\#path` vs `%%srpath%%`), several search modes (HTML, ignore-whitespace,
  boolean, clipboard), file operations on results, script format
  (`.snrscript` JSON vs `.srs` ASCII), and CLI shape all diverge from the
  Windows original. The roadmap above plans the work needed to close the
  gap.

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
