#!/usr/bin/env bash
# Install the "Print to Purple PDF" macOS PDF Service standalone (without
# launching the app). Useful during development. The app also auto-installs
# this on first launch.
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "PDF Service is macOS-only." >&2
  exit 1
fi

DEST_DIR="$HOME/Library/PDF Services"
DEST="$DEST_DIR/Print to Purple PDF"
CAPTURE_DIR="$HOME/Documents/Purple PDF/Captures"

mkdir -p "$DEST_DIR" "$CAPTURE_DIR"

cat > "$DEST" <<'SCRIPT'
#!/bin/bash
# Purple PDF — macOS PDF Service
set -u
title="${1:-Document}"
src="${4:-}"
if [ -z "$src" ] || [ ! -f "$src" ]; then exit 1; fi
safe=$(printf '%s' "$title" | tr -c 'A-Za-z0-9._- ' '_')
ts=$(date +%Y%m%d-%H%M%S)
dest_dir="$HOME/Documents/Purple PDF/Captures"
mkdir -p "$dest_dir"
dest="$dest_dir/${safe}-${ts}.pdf"
cp "$src" "$dest"
open -a "Purple PDF" "$dest"
SCRIPT

chmod +x "$DEST"
echo "Installed: $DEST"
echo "Captures:  $CAPTURE_DIR"
