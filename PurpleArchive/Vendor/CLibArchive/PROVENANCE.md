# CLibArchive — provenance

Vendored **libarchive 3.7.7**, BSD-2-Clause.

## Source

- Upstream: <https://github.com/libarchive/libarchive>
- Release tag: `v3.7.7`
- Tarball: `libarchive-3.7.7.tar.gz`
- **SHA-256:** `4cc540a3e9a1eebdefa1045d2e4184831100667e6d7d5b315bb1cbc951f8ddff`

## What's vendored

- `Sources/CLibArchive/src/*.c`, `*.h` — the verbatim `libarchive/` library
  tree (131 `.c`, 40 `.h`). The CLI front-ends (bsdtar/bsdcpio/bsdcat/bsdunzip)
  are **not** vendored; we only build the library.
- `Sources/CLibArchive/src/config.h` — generated **once** by CMake for arm64
  macOS (see flags below). Regenerating it is the only step that needs CMake.
- `Sources/CLibArchive/include/archive.h`, `archive_entry.h` — the public
  API, exposed as the Swift-importable `CLibArchive` module.
- `Sources/CLibArchive/include_lzma/` — liblzma **API headers only**, copied
  from **xz 5.6.3** (`xz-5.6.3.tar.gz`,
  SHA-256 `b1d45295d3f71f25a4c9101bd7c8d16cb56348bbef3bbc738da0351e17c73317`).
  The macOS SDK ships no `lzma.h`, so we vendor the headers and link the
  ubiquitous **system** `liblzma` (dyld shared cache). The 5.x API is
  forward-compatible; libarchive only calls long-stable symbols.

## Compression-filter dependencies

| Filter | Header source        | Library (link) |
|--------|----------------------|----------------|
| zlib   | macOS SDK `zlib.h`   | system `-lz`   |
| bzip2  | macOS SDK `bzlib.h`  | system `-lbz2` |
| xz     | vendored (xz 5.6.3)  | system `-llzma`|
| zstd   | sibling `CZstd`      | **static** (vendored, compiled in) |

## CMake configure flags (config.h regeneration)

```sh
cmake .. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DENABLE_OPENSSL=OFF -DENABLE_LIBB2=OFF -DENABLE_LZ4=OFF -DENABLE_LZO=OFF \
  -DENABLE_LIBXML2=OFF -DENABLE_EXPAT=OFF -DENABLE_PCREPOSIX=OFF -DENABLE_NETTLE=OFF \
  -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF -DENABLE_TEST=OFF \
  -DENABLE_ZSTD=ON -DENABLE_LZMA=ON -DENABLE_ZLIB=ON -DENABLE_BZip2=ON -DENABLE_ICONV=ON
```

## Regenerate

```sh
Scripts/build-vendored.sh libarchive
```

## Notes / future work

- **lz4** and **lzo** filters are disabled (no SDK headers; not yet vendored).
  Add a `CLz4` package and flip `HAVE_LIBLZ4`/`HAVE_LZ4_H` in `config.h` when
  needed.
- **7z creation** is not provided by libarchive (read-only); a p7zip/lib7zip
  backend lands in Phase 3.
