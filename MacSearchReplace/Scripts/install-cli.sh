#!/usr/bin/env bash
#
# install-cli.sh — symlink the built `snr` CLI into /usr/local/bin.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_PATH="$(cd "$ROOT" && swift build -c release --show-bin-path)"
SRC="$BIN_PATH/snr"
DEST="/usr/local/bin/snr"

if [[ ! -x "$SRC" ]]; then
    echo "Building snr first..."
    (cd "$ROOT" && swift build -c release --product snr)
fi

mkdir -p /usr/local/bin
ln -sf "$SRC" "$DEST"
echo "✓ Symlinked $DEST → $SRC"
