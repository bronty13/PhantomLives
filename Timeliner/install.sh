#!/bin/bash
# Reinstall the freshly-built Timeliner.app into /Applications/.
#
# Usage:
#     ./install.sh           # quit running, replace, relaunch
#     ./install.sh --no-open # quit running, replace, leave closed
#
# The .app must already exist in this directory — run `./build-app.sh`
# first.
set -euo pipefail

cd "$(dirname "$0")"

SRC="$PWD/Timeliner.app"
DST="/Applications/Timeliner.app"
OPEN_AFTER=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo "error: $SRC does not exist. Run ./build-app.sh first." >&2
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
    rm -rf "$DST"
fi
echo "Copying $SRC → $DST"
ditto --noextattr "$SRC" "$DST"

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
