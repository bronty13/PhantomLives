#!/usr/bin/env bash
#
# build-vendored.sh — regenerate PurpleArchive's vendored C sources from pinned,
# SHA-256-verified upstream release tarballs.
#
# The generated sources are COMMITTED to the repo (the SQLCipher/PurpleLife
# pattern), so a normal build needs neither this script nor a network. Run this
# only to bump a vendored library's version or to reproduce the sources from
# scratch.
#
# Usage:
#   Scripts/build-vendored.sh                # all libraries
#   Scripts/build-vendored.sh zstd           # just zstd
#   Scripts/build-vendored.sh libarchive     # just libarchive (needs cmake)
#
# Requirements: curl, shasum, tar, and (for libarchive) cmake >= 3.5.

set -euo pipefail

# --- pinned versions + checksums ---------------------------------------------
ZSTD_VERSION=1.5.6
ZSTD_SHA256=8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1

LIBARCHIVE_VERSION=3.7.7
LIBARCHIVE_SHA256=4cc540a3e9a1eebdefa1045d2e4184831100667e6d7d5b315bb1cbc951f8ddff

XZ_VERSION=5.6.3   # liblzma API headers only
XZ_SHA256=b1d45295d3f71f25a4c9101bd7c8d16cb56348bbef3bbc738da0351e17c73317

# --- paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR="$ROOT/Vendor"
STAGE="${STAGE:-/tmp/purplearchive-vendor}"
mkdir -p "$STAGE"

CMAKE="${CMAKE:-$(command -v cmake || echo /opt/homebrew/bin/cmake)}"

log() { printf '\033[35m▸ %s\033[0m\n' "$*"; }

fetch() { # name url sha256 outfile
  local name="$1" url="$2" sha="$3" out="$STAGE/$4"
  if [[ -f "$out" ]] && shasum -a 256 "$out" | grep -q "$sha"; then
    log "$name: cached, checksum OK"
  else
    log "$name: downloading"
    curl -fsSL -o "$out" "$url"
    echo "$sha  $out" | shasum -a 256 -c - || {
      echo "CHECKSUM MISMATCH for $name" >&2; exit 1; }
  fi
}

build_zstd() {
  fetch "zstd $ZSTD_VERSION" \
    "https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz" \
    "$ZSTD_SHA256" zstd.tar.gz
  rm -rf "$STAGE/zstd-$ZSTD_VERSION"; tar xzf "$STAGE/zstd.tar.gz" -C "$STAGE"
  local sf="$STAGE/zstd-$ZSTD_VERSION/build/single_file_libs"
  ( cd "$sf" && ./create_single_file_library.sh >/dev/null )
  local dest="$VENDOR/CZstd/Sources/CZstd"
  mkdir -p "$dest/include"
  cp "$sf/zstd.c" "$dest/zstd.c"
  cp "$STAGE/zstd-$ZSTD_VERSION/lib/zstd.h" "$dest/include/zstd.h"
  cp "$STAGE/zstd-$ZSTD_VERSION/lib/zstd_errors.h" "$dest/include/zstd_errors.h"
  log "zstd: amalgamation written to $dest"
}

build_libarchive() {
  fetch "libarchive $LIBARCHIVE_VERSION" \
    "https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VERSION/libarchive-$LIBARCHIVE_VERSION.tar.gz" \
    "$LIBARCHIVE_SHA256" libarchive.tar.gz
  fetch "xz $XZ_VERSION (lzma headers)" \
    "https://github.com/tukaani-project/xz/releases/download/v$XZ_VERSION/xz-$XZ_VERSION.tar.gz" \
    "$XZ_SHA256" xz.tar.gz
  rm -rf "$STAGE/libarchive-$LIBARCHIVE_VERSION" "$STAGE/xz-$XZ_VERSION"
  tar xzf "$STAGE/libarchive.tar.gz" -C "$STAGE"
  tar xzf "$STAGE/xz.tar.gz" -C "$STAGE"

  local la="$STAGE/libarchive-$LIBARCHIVE_VERSION"
  log "libarchive: generating config.h with cmake"
  rm -rf "$la/_cmbuild"; mkdir -p "$la/_cmbuild"
  ( cd "$la/_cmbuild" && "$CMAKE" .. \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DENABLE_OPENSSL=OFF -DENABLE_LIBB2=OFF -DENABLE_LZ4=OFF -DENABLE_LZO=OFF \
      -DENABLE_LIBXML2=OFF -DENABLE_EXPAT=OFF -DENABLE_PCREPOSIX=OFF -DENABLE_NETTLE=OFF \
      -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF -DENABLE_TEST=OFF \
      -DENABLE_ZSTD=ON -DENABLE_LZMA=ON -DENABLE_ZLIB=ON -DENABLE_BZip2=ON -DENABLE_ICONV=ON \
      >/dev/null )

  local dest="$VENDOR/CLibArchive/Sources/CLibArchive"
  rm -rf "$dest/src" "$dest/include" "$dest/include_lzma"
  mkdir -p "$dest/src" "$dest/include" "$dest/include_lzma"
  cp "$la"/libarchive/*.c "$la"/libarchive/*.h "$dest/src/"
  cp "$la/_cmbuild/config.h" "$dest/src/config.h"
  cp "$la"/libarchive/archive.h "$la"/libarchive/archive_entry.h "$dest/include/"
  cp "$STAGE/xz-$XZ_VERSION/src/liblzma/api/lzma.h" "$dest/include_lzma/"
  cp -R "$STAGE/xz-$XZ_VERSION/src/liblzma/api/lzma" "$dest/include_lzma/"
  log "libarchive: $(ls "$dest/src"/*.c | wc -l | tr -d ' ') sources written to $dest"
}

case "${1:-all}" in
  zstd)        build_zstd ;;
  libarchive)  build_libarchive ;;
  all)         build_zstd; build_libarchive ;;
  *) echo "usage: $0 [zstd|libarchive|all]" >&2; exit 2 ;;
esac
log "done"
