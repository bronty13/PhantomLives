# CUnrar — provenance

Vendored **RARLAB unrar 7.1.6** for RAR / RAR5 **extraction**.

## Source

- Upstream: <https://www.rarlab.com/rar/unrarsrc-7.1.6.tar.gz>
- **SHA-256:** `ca5e1da37dd6fa1b78bb5ed675486413f79e4a917709744aa04b6f93dfd914f0`

## License — extract-only freeware (see `LICENSE`)

The unrar source is freeware: it **may be used to handle RAR archives** (read /
extract) in any software, but it **may NOT be used to re-create the RAR
compression algorithm** or to create RAR archives, and the license text must be
shipped. PurpleArchive uses it strictly for reading — RAR creation is never
offered.

## What's vendored

`Sources/CUnrar/unrar/` is the verbatim unrar source tree (all `.cpp`/`.hpp`).
The build compiles **only the library translation units** the upstream
`makefile` lists (`OBJECTS` + `LIB_OBJ`, 48 files, with `-DRARDLL`); the other 37
`.cpp` are `#include`d by those and are listed in `Package.swift`'s `exclude:`.

`Sources/CUnrar/cunrar.{h,cpp}` is PurpleArchive's thin **C shim** over unrar's
C++ `RAR*` "dll" API (`dll.hpp`), so Swift imports `CUnrar` as a plain C module:
`cunrar_open` / `_next` / `_skip` / `_extract` / `_test` / `_close`.

## Build flags

`-DRARDLL -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE`, C++ (libc++). `_UNIX` /
`HANDLE` come from unrar's `os.hpp` via `rar.hpp` (included first by the shim).
`RAR_SMP` (multithreaded unpack) is intentionally off for a simpler, portable
build; `threadpool.cpp` compiles inert.

## Why both unrar and libarchive

libarchive reads ~8/9 RAR variants but fails on **RAR5 + recovery record**
(`error 0`). unrar covers 100% and uses recovery data during extraction, so
`ArchiveService` routes all RAR (by `Rar!\x1a\x07` magic) to `UnrarEngine`.
Gated by `RarReadTests` against the committed `Tests/ArchiveKitTests/RarCorpus`
(from github.com/ssokolow/rar-test-files): all variants list+extract to the
expected content.

## Regenerate

```sh
curl -fsSLO https://www.rarlab.com/rar/unrarsrc-7.1.6.tar.gz && tar xzf unrarsrc-7.1.6.tar.gz
cp unrar/*.cpp unrar/*.hpp <repo>/Vendor/CUnrar/Sources/CUnrar/unrar/
cp unrar/license.txt       <repo>/Vendor/CUnrar/LICENSE
# exclude list in Package.swift = all .cpp minus makefile OBJECTS+LIB_OBJ
```
