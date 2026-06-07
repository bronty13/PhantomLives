# CPeeler — provenance

Vendored **peeler** — a small C99 library for unpacking legacy Macintosh
archive formats. **MIT licensed** (see `LICENSE`).

## Source

- Upstream: <https://github.com/pappadf/peeler>
- Pinned commit: `855e3fab0f038da282700742818f6c7c43a2c59f`

## What's vendored

The library only (not the `cmd/` CLI):

- `Sources/CPeeler/peeler.c`, `util.c`, `err.c` — library roots (from `lib/`).
- `Sources/CPeeler/formats/{bin,cpt,hqx,sit,sit3,sit13,sit15}.c` — per-format
  decoders (from `lib/formats/`).
- `Sources/CPeeler/internal.h` — private header (from `lib/`).
- `Sources/CPeeler/include/peeler.h` — public API (the Swift-importable module).

## Formats

- **StuffIt** (`.sit`) — including methods 13, 14, and 15 ("Arsenic")
- **Compact Pro** (`.cpt`)
- **BinHex** (`.hqx`) — 4.0
- **MacBinary** (`.bin`)
- Nested wraps (e.g. `.sit.hqx`) handled by `peel`/`peel_path`.

## ⚠️ AI-generated — trusted only because it's verified

peeler is, by its author's own statement, largely AI-generated. PurpleArchive
therefore does **not** trust it on reputation. It is gated by
`Tests/ArchiveKitTests/PeelerLegacyTests.swift`, which extracts the committed
redistributable corpus (`Tests/ArchiveKitTests/LegacyCorpus/` — StuffIt
4.5/6.5.1/7, Compact Pro 1.33, BinHex, MacBinary) through our `PeelerEngine` and
**byte-verifies every data fork against ground-truth MD5s**. At adoption the full
upstream corpus (22 archives) passed 216/216 data-fork checksums. If a future
peeler bump breaks any checksum, the test fails — re-validate before shipping.

## Regenerate

```sh
git clone https://github.com/pappadf/peeler && cd peeler && git checkout 855e3fab
cp lib/{peeler,util,err}.c            <repo>/Vendor/CPeeler/Sources/CPeeler/
cp lib/formats/*.c                    <repo>/Vendor/CPeeler/Sources/CPeeler/formats/
cp lib/internal.h                     <repo>/Vendor/CPeeler/Sources/CPeeler/
cp include/peeler.h                   <repo>/Vendor/CPeeler/Sources/CPeeler/include/
cp LICENSE                            <repo>/Vendor/CPeeler/
```
