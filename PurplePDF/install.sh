#!/bin/bash
# Reinstall the freshly-built Purple PDF.app into /Applications/.
#
# Usage:
#     ./install.sh           # quit running, replace, relaunch
#     ./install.sh --no-open # quit running, replace, leave closed
#
# The .app must already exist under ./dist/ — run `./build-app.sh`
# first if you need to rebuild after a code change.
#
# Per the PhantomLives `install.sh` standard (root CLAUDE.md): macOS
# TCC entitlements, Launch Services, Spotlight, and Cmd+Tab all key
# off the resolved bundle path. Installing from the repo tree poisons
# the Privacy DB with stale grants on every rebuild; installing to
# `/Applications` keeps a single stable cdhash entry.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Purple PDF"
APP_BUNDLE="${APP_NAME}.app"
DST="/Applications/${APP_BUNDLE}"
OPEN_AFTER=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# electron-builder writes mac/arm64 -> mac-arm64, x64 -> mac, universal -> mac-universal.
SRC=""
for d in "dist/mac-arm64" "dist/mac" "dist/mac-x64" "dist/mac-universal"; do
    if [ -d "$d/$APP_BUNDLE" ]; then
        SRC="$PWD/$d/$APP_BUNDLE"
        break
    fi
done
if [ -z "$SRC" ]; then
    echo "error: $APP_BUNDLE not found under dist/. Run ./build-app.sh first." >&2
    ls -la dist/ 2>/dev/null || true
    exit 1
fi

echo "Quitting any running ${APP_NAME}..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
# Give Launch Services a beat to release the bundle lock.
sleep 1

if [ -d "$DST" ]; then
    echo "Removing existing $DST"
    if ! rm -rf "$DST" 2>/dev/null; then
        echo "  (need sudo)"
        sudo rm -rf "$DST"
    fi
fi

echo "Copying $SRC → $DST"
# --noextattr strips iCloud File Provider xattrs that re-attach mid-copy
# and break `codesign --verify` on ~/Documents/GitHub/-rooted checkouts.
if ! ditto --noextattr "$SRC" "$DST" 2>/dev/null; then
    echo "  (need sudo)"
    sudo ditto --noextattr "$SRC" "$DST"
fi

# Strip Gatekeeper quarantine so an ad-hoc-signed dev build launches cleanly.
xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true

if [ "$OPEN_AFTER" -eq 1 ]; then
    echo "Launching $DST"
    open "$DST"
else
    echo "Skipping launch (--no-open)."
fi
