# PurpleArchive

A world-class, Apple-Silicon-native archive/unarchive utility for macOS — a
stunning SwiftUI app **and** a powerful CLI (`parc`) sharing one engine, built
to read and create *every* archive format from today and yesteryear. The goal:
the last archive tool you'll ever install on a Mac.

> **Status: Phase 1 (MVP) complete.** Vendoring foundation + the full engine
> (extract/create/test/hash across zip·tar·gz·bz2·xz·zst, AES-256, zip-slip-safe,
> bounded-concurrency batches), the `parc` CLI, and a SwiftUI app (HStack
> sidebar, browser, drag-to-compress, Settings + Backup) that builds, installs,
> and launches. Legacy formats (RAR/StuffIt), encoding fix, vault, Quick Look,
> and Sparkle are next — see [CHANGELOG.md](CHANGELOG.md) and [HANDOFF.md](HANDOFF.md).

## Architecture

A layered design (see [`HANDOFF.md`](HANDOFF.md) once it lands):

- **`ArchiveKit`** — the engine framework shared by the GUI, the CLI, and the
  app-extensions. Wraps several vendored C libraries behind a single Swift
  surface; nothing above it touches raw pointers.
- **Backends** — `LibArchiveEngine` (broad coverage: zip/7z-read/tar/cab/iso/
  rar5-read/cpio/…), `ZstdEngine` (multithreaded `.zst`/`.tar.zst` create),
  later `AppleArchiveEngine`, `XADMasterEngine` (legacy Mac), `UnrarEngine`.
- **`parc`** — the CLI, same engine as the GUI.

## Vendored libraries

Sources are committed (no network or extra tools needed for a normal build).
See each `Vendor/*/PROVENANCE.md` for pinned versions + SHA-256s.

| Package | Library | License | Linkage |
|---------|---------|---------|---------|
| `Vendor/CLibArchive` | libarchive 3.7.7 | BSD-2-Clause | compiled in |
| `Vendor/CZstd` | Zstandard 1.5.6 | BSD-3-Clause | compiled in (static) |
| zlib / bzip2 / xz | system libs | — | dynamically linked |

Regenerate from upstream: `Scripts/build-vendored.sh` (needs `cmake` for
libarchive's `config.h`).

## Build & test (development)

```sh
swift build -c release            # ArchiveKit + parc
swift test                        # via full Xcode toolchain; ./run-tests.sh wraps this
.build/release/parc l some.zip    # list any supported archive
.build/release/parc version       # engine versions
```

The macOS `.app` (with Quick Look / Thumbnail / Finder Sync extensions and
Sparkle auto-update) is assembled via XcodeGen — `./build-app.sh` once that
lands.

## Default output location

Extractions default to `~/Downloads/PurpleArchive/` (override persists);
internal cache/config lives under `~/Library/Application Support/PurpleArchive/`.
