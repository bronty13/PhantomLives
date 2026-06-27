#!/usr/bin/env bash
# Deterministically generates build/icon.icns + build/icon.png from icon.svg
# (the plain-text source of truth). Needs rsvg-convert + iconutil (macOS).
# Run by build-app.sh before packaging; the .icns/.png are gitignored artifacts.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "ERROR: rsvg-convert not found (brew install librsvg)." >&2
  exit 1
fi

ICONSET="icon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() { rsvg-convert -w "$2" -h "$2" icon.svg -o "$ICONSET/$1"; }
render icon_16x16.png 16
render icon_16x16@2x.png 32
render icon_32x32.png 32
render icon_32x32@2x.png 64
render icon_128x128.png 128
render icon_128x128@2x.png 256
render icon_256x256.png 256
render icon_256x256@2x.png 512
render icon_512x512.png 512
render icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET" -o icon.icns
rsvg-convert -w 1024 -h 1024 icon.svg -o icon.png
rm -rf "$ICONSET"
echo "Generated build/icon.icns + build/icon.png"
