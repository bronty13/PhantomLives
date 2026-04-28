# Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Apps/MacSearchReplace  (SwiftUI + AppKit)                  │
│   Views ── ViewModels ── async/await + ObservableObject     │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Packages/SnRCore   (Swift Package, no UI deps)             │
│  SnRCore   → Job orchestrator, public façade                │
│  SnRSearch → ripgrep Process wrapper, JSON stream parser,   │
│              native fallback for tests/no-rg systems        │
│  SnRReplace→ streaming text rewriter, binary/hex engine,    │
│              counter operator, path-token interpolation,    │
│              APFS-clonefile BackupManager                   │
│  SnRArchive→ ZIP / .docx / .xlsx / .pptx in-place rewrite   │
│              (currently shells to /usr/bin/{zip,unzip})     │
│  SnREncoding → BOM/ASCII/UTF-8 detection w/ Latin-1 fallback│
│  SnRScript → .snrscript v1 model + load/save                │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
              ┌────────────────────────────┐
              │  Apps/MacSearchReplace/    │
              │   Vendored/rg              │  ← fetched by Scripts/
              │  /usr/bin/{zip,unzip}      │
              └────────────────────────────┘

Apps/snr-cli ────────────► (same SnRCore)
```

## Concurrency
- Each subsystem is isolated. `BackupManager` is an actor; `Replacer` is a
  value type whose `apply` runs on a detached `Task.detached(priority:.userInitiated)`.
- The UI never blocks the main thread: all engine calls go through `async/await`.

## Atomicity
- Every text/binary rewrite is written to a sibling temp file and committed
  via `FileManager.replaceItemAt` (which is atomic on the same volume).
- The pre-write `clonefile(2)` snapshot is taken before commit, so a crash
  during rewrite leaves the original intact.

## Encoding strategy
1. Sniff BOM (UTF-8/16/32).
2. Pure ASCII fast path on first 64 KB.
3. Validate as UTF-8.
4. Fall back to Latin-1 (lossless single-byte).

`uchardet` integration is deferred; today's heuristic covers ~95% of real
input. We always preserve a leading BOM if one was present in the original.

## Personal-use distribution
- No sandboxing (no MAS).
- Ad-hoc codesigned `.app` bundle assembled by `Scripts/build-app.sh`.
- Bundled ripgrep lives at `…/Contents/MacOS/rg` and is located via
  `RipgrepLocator` which checks `$SNR_RIPGREP_PATH`, the executable's
  directory, common Homebrew paths, then `which rg`.
