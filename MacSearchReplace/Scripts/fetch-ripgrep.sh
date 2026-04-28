#!/usr/bin/env bash
#
# fetch-ripgrep.sh — download a pinned ripgrep release for both arm64 and x86_64,
# stitch a universal binary with `lipo`, and place it in
# Apps/MacSearchReplace/Vendored/rg.
#
# Personal-use vendoring: ripgrep is MIT-licensed.

set -euo pipefail

RG_VERSION="${RG_VERSION:-14.1.1}"
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/Apps/MacSearchReplace/Vendored"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$DEST_DIR"

fetch() {
    local arch="$1"   # aarch64 or x86_64
    local triple="$2" # apple-darwin
    local name="ripgrep-${RG_VERSION}-${arch}-${triple}"
    local url="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/${name}.tar.gz"
    echo "→ Downloading ${name}"
    curl -fsSL "$url" -o "$TMP_DIR/${name}.tar.gz"
    tar -xzf "$TMP_DIR/${name}.tar.gz" -C "$TMP_DIR"
    cp "$TMP_DIR/${name}/rg" "$TMP_DIR/rg-${arch}"
    chmod +x "$TMP_DIR/rg-${arch}"
}

fetch aarch64 apple-darwin
fetch x86_64  apple-darwin

echo "→ Combining into universal binary"
lipo -create \
    "$TMP_DIR/rg-aarch64" \
    "$TMP_DIR/rg-x86_64" \
    -output "$DEST_DIR/rg"
chmod +x "$DEST_DIR/rg"

echo "✓ Vendored ripgrep ${RG_VERSION} → $DEST_DIR/rg"
file "$DEST_DIR/rg"
"$DEST_DIR/rg" --version | head -1
