# Engineering Handoff — MacSearchReplace

Single-author project; this document captures everything a successor engineer needs to keep moving.

## TL;DR

A native macOS Search & Replace utility, Funduc-equivalent. SwiftUI front end, Swift Package Manager build, vendored `ripgrep` for the hot search path, atomic file replace + APFS-clone backups for safety. CLI sibling (`snr`) shares the same core library.

Latest commit on `main` ships **Phase 4 — Funduc parity**. See `README.md` for the parity matrix.

## Architecture

```
┌─────────────────────────────────────────┐    ┌──────────────┐
│ Apps/MacSearchReplace (SwiftUI + AppKit)│    │ Apps/snr-cli │
└──────────────┬──────────────────────────┘    └──────┬───────┘
               │                                      │
               ▼                                      ▼
        ┌──────────────────────────────────────────────┐
        │ Packages/SnRCore  (umbrella, re-exports)     │
        ├──────────────────────────────────────────────┤
        │  SnRSearch    ripgrep stream + native fallbk │
        │  SnRReplace   atomic replace + counter       │
        │  SnREncoding  charset detect + transcode     │
        │  SnRArchive   ZIP / OOXML / TAR rewrite      │
        │  SnRPDF       PDFKit text search (read-only) │
        │  SnRScript    .snrscript v1 + v2             │
        └──────────────────────────────────────────────┘
                            │
                            ▼
                   /usr/bin/tar, vendored rg
```

Full diagrams in [`Docs/architecture.md`](architecture.md).

### Concurrency model

- All I/O lives in `actor`s or `nonisolated async` functions.
- The `Searcher.stream(spec:)` is an `AsyncThrowingStream<FileMatches,Error>`. Cancelling the consuming `Task` triggers `continuation.onTermination`, which terminates the `ripgrep` `Process` cleanly.
- The view model is `@MainActor`. Long work is dispatched off-main via detached `Task`s.
- `Preferences.shared` is a `@MainActor`-isolated singleton over `UserDefaults`.

### Safety invariants

1. **Never mutate in place** — `Replacer` writes a sibling `*.snr-tmp` file, then `rename()`s it (atomic on APFS).
2. **Always back up first** — `BackupManager` creates an APFS clone (`clonefile(2)`) before the rename. This is O(1) and consumes no extra disk until the original diverges.
3. **Backup manifest is the source of truth for undo** — `manifest.json` lists every clone path → original path. `snr restore <session>` reverses them.
4. **Length-preserving binary mode** — `Replacer` refuses to grow or shrink a binary file under hex mode, to keep offsets stable.

## Repo layout

| Path                                 | Purpose |
|--------------------------------------|---------|
| `Package.swift`                      | Umbrella SPM manifest |
| `Packages/SnRCore/`                  | Core library, six modules |
| `Apps/MacSearchReplace/`             | SwiftUI app + Info.plist + entitlements |
| `Apps/MacSearchReplace/Vendored/rg`  | Vendored ripgrep binary (gitignored; fetched by `Scripts/fetch-ripgrep.sh`) |
| `Apps/snr-cli/`                      | `snr` command-line tool |
| `Scripts/`                           | `build-app.sh`, `fetch-ripgrep.sh`, etc. |
| `Tests/smoke.sh`                     | End-to-end CLI smoke harness |
| `Packages/SnRCore/Tests/*`           | Unit tests (swift-testing — needs full Xcode) |
| `Docs/`                              | Architecture, format docs, regex cheat sheet, user docs |

## Build & run

```bash
./Scripts/fetch-ripgrep.sh        # one-time: vendors ripgrep
swift build                        # builds library + snr CLI + app target
./Scripts/build-app.sh             # bundles + ad-hoc signs the .app
open build/MacSearchReplace.app
```

## Test strategy

| Layer            | Tool              | Status |
|------------------|-------------------|--------|
| Library units    | `swift-testing`   | Source committed; **needs full Xcode** to compile (`Testing` module ships with Xcode, not the bare CLT). Out of scope until a CI runner with Xcode exists. |
| End-to-end / CLI | `Tests/smoke.sh`  | **16 tests, green.** Runs without Xcode. Used as the gate. |
| GUI              | Manual smoke      | After every wave: launch app, run a search, verify Stop/Filters/Export. |

To run smoke tests:

```bash
./Tests/smoke.sh
```

## Coding conventions

- Swift 5.9+/6 syntax; `Sendable`-clean across module boundaries.
- One module per concern under `Packages/SnRCore/Sources/<ModuleName>/`.
- `SnRCore.swift` re-exports submodules with `@_exported import` — UI/CLI only ever `import SnRCore`.
- Public API uses `URL`/`Data`/`String`. Avoid leaking `Process`, `FileHandle`, etc.
- New view-model state goes through `@Published` on `SearchReplaceViewModel`.

## What's done (Phase 0–4)

See the parity matrix in `README.md`. In short: full Funduc workflow, plus PDFs and OOXML, plus a CLI, plus saved multi-step scripts.

## What's deferred (Phase 5 candidates)

- **OOXML round-trip fixtures** — pipeline works, but no `.docx` corpus tests yet.
- **Auto-binary detection on hits** — currently the user toggles "open in binary editor".
- **Performance pass** — bound result buffer; chunked I/O for files > 200 MB.
- **HTML entity / Unicode lookup tables** — Funduc has these; we don't.
- **Boolean gating in scripts** — Funduc lets steps depend on prior step counts.
- **Inline edit in context viewer** — currently read-only preview.
- **AppleScript dictionary**.
- **Localization beyond English**.

The `inbox_entries` and `todos` tables in the session DB carry a granular backlog with IDs (`p4-perf-pass`, `p4-large-file`, `p4-text-binary-detect`, `p4-archive-ooxml`).

## Known caveats

1. **swift-testing is unrunnable on a CLT-only system** — the `Testing.framework` ships only with full Xcode. The `Packages/SnRCore/Tests/**.swift` files compile as documentation of intent; CI must have Xcode to run them.
2. **Ripgrep cancellation race** — `task.terminate()` sends SIGTERM. If `rg` is mid-write to the pipe the `for await` loop might see one extra line before the stream closes. Harmless but worth knowing.
3. **PDFKit packed line numbers** — `Hit.line` is `pageNumber*10000 + lineWithinPage`. Decode with `PDFSearcher.decodeLine(_:)`. This avoids a schema migration but is *load-bearing*: don't break the convention.
4. **OOXML rewrite** — works, but the smoke harness doesn't yet ship a `.docx` fixture. Manual test before relying on it for production docs.
5. **Tar implementation shells out** to `/usr/bin/tar` and uses different flag combinations for `-z` / non-`-z`. See `TarRewriter.swift`.
6. **No Mac App Store path** — entitlements assume hardened runtime *off*; we shell out to `rg` and `tar`. Sandboxing would require the executables to be in the bundle and would also break Spotlight enumeration.

## Release / handoff checklist

Before tagging a release:

```bash
swift build -c release
./Tests/smoke.sh                      # must be green
./Scripts/build-app.sh
codesign -dvv build/MacSearchReplace.app | grep "Signature="
git tag v<X.Y.Z> && git push --tags
```

Update `CHANGELOG.md` and bump `SnR.version` in `SnRCore.swift`.

## Useful pointers

- Funduc reference docs: <https://www.funduc.com/search_replace.htm> · <https://www.funduc.com/replace_studio_version_matrix.htm>
- ripgrep manual: `man rg`, <https://github.com/BurntSushi/ripgrep>
- PDFKit: <https://developer.apple.com/documentation/pdfkit>
