#!/bin/bash
# Reinstall the freshly-built Purple Tree.app into /Applications/.
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
# `/Applications` keeps a single stable cdhash entry. This matters
# especially for Purple Tree, which needs a stable cdhash for the
# Full Disk Access grant used to scan system / Library folders.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Purple Tree"
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

# ---- Stale-instance-proof termination (PhantomLives standard) ----
# A graceful quit can be blocked by a confirmation dialog or hung run loop,
# leaving the old process alive so `open` re-focuses the STALE copy. Force-kill
# until the process is provably gone. See CLAUDE.md "Stale running applications"
# + docs/install-sh-standard.md.
BUNDLE="$DST"
APP_DISPLAY="$(basename "$BUNDLE" .app)"
PROC="$BUNDLE/Contents/MacOS/"          # processes running from this bundle

echo "Terminating any running ${APP_DISPLAY} (force)..."
osascript -e "tell application \"${APP_DISPLAY}\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 50); do
    pgrep -f "$PROC" >/dev/null 2>&1 || break
    pkill -9 -f "$PROC" 2>/dev/null || true
    sleep 0.2
done
if pgrep -f "$PROC" >/dev/null 2>&1; then
    echo "error: could not terminate running ${APP_DISPLAY} — aborting to avoid a stale install." >&2
    exit 1
fi

if [ -d "$DST" ]; then
    echo "Removing existing $DST"
    if ! rm -rf "$DST" 2>/dev/null; then
        echo "  (need sudo)"
        sudo rm -rf "$DST"
    fi
fi

echo "Copying $SRC → $DST"
# --noextattr strips iCloud File Provider xattrs that re-attach mid-copy
# and break `codesign --verify` on iCloud-rooted checkouts.
if ! ditto --noextattr "$SRC" "$DST" 2>/dev/null; then
    echo "  (need sudo)"
    sudo ditto --noextattr "$SRC" "$DST"
fi

# Strip Gatekeeper quarantine so an ad-hoc-signed dev build launches cleanly.
xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true

# ---- Relaunch a guaranteed-new instance + prove it's the new build ----
if [ "${OPEN_AFTER:-1}" -ne 1 ]; then
    echo "Skipping launch (--no-open)."
    exit 0
fi
EXEC_PATH="$BUNDLE/Contents/MacOS/$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleExecutable 2>/dev/null)"
BIN_EPOCH=$(stat -f %m "$EXEC_PATH" 2>/dev/null || echo 0)
echo "Launching $BUNDLE"
open -n "$BUNDLE"
FRESH_PID=""
for _ in $(seq 1 50); do
    FRESH_PID=$(pgrep -nf "$PROC" || true)
    [ -n "$FRESH_PID" ] && break
    sleep 0.2
done
if [ -z "$FRESH_PID" ]; then echo "error: ${APP_DISPLAY} did not start after install." >&2; exit 1; fi
START_STR=$(ps -o lstart= -p "$FRESH_PID")
START_EPOCH=$(date -j -f "%a %b %e %T %Y" "$START_STR" +%s 2>/dev/null || echo 0)
if [ "$START_EPOCH" -lt "$((BIN_EPOCH - 2))" ]; then
    echo "error: running ${APP_DISPLAY} (started $START_STR) predates the new binary — stale instance survived." >&2
    exit 1
fi
VER=$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "Verified: ${APP_DISPLAY} ${VER} running fresh (pid $FRESH_PID, started $START_STR)."
