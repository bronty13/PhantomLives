# CZstd — provenance

Vendored **Zstandard 1.5.6** (Facebook/Meta), BSD-3-Clause OR GPL-2.0. We use
it under the BSD-3-Clause option.

## Source

- Upstream: <https://github.com/facebook/zstd>
- Release tag: `v1.5.6`
- Tarball: `zstd-1.5.6.tar.gz`
- **SHA-256:** `8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1`

## What's vendored

- `Sources/CZstd/zstd.c` — the **single-file amalgamation** produced by the
  upstream `build/single_file_libs/create_single_file_library.sh` (the full
  library: common + compress + decompress + dictBuilder). ~51k lines.
- `Sources/CZstd/include/zstd.h`, `zstd_errors.h` — public API headers copied
  verbatim from the release `lib/` tree.

## Build flags (see `Package.swift`)

- `ZSTD_DISABLE_ASM` — compile the portable C decoder on every arch (identical
  Intel/Apple-Silicon build; the x86-64 BMI2 asm path is dropped).
- The amalgamation already `#define ZSTD_MULTITHREAD`s itself, enabling the
  internal worker-thread pool (`ZSTD_c_nbWorkers`).

## Regenerate

```sh
Scripts/build-vendored.sh zstd
```
