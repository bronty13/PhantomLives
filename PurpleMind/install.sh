#!/usr/bin/env bash
# install.sh — Mac side of the PhantomLives install convention.
# Replaces /Applications/PurpleMind.app with the freshly-built bundle and
# relaunches it so TCC entitlements stay anchored to a stable cdhash.
#
# Usage:
#   ./install.sh            # quit + replace + relaunch
#   ./install.sh --no-open  # quit + replace, but do not relaunch

set -euo pipefail

NO_OPEN=0
for arg in "$@"; do
  case "$arg" in
    --no-open) NO_OPEN=1 ;;
    *) ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_APP="$PROJECT_DIR/src-tauri/target/release/bundle/macos/PurpleMind.app"
INSTALL_PATH="/Applications/PurpleMind.app"

if [ ! -d "$LOCAL_APP" ]; then
  echo "❌ No build found at $LOCAL_APP"
  echo "   Run ./build-app.sh first."
  exit 1
fi

# ---- Stale-instance-proof termination (PhantomLives standard) ----
# A graceful quit can be blocked by a confirmation dialog or hung run loop,
# leaving the old process alive so `open` re-focuses the STALE copy. Force-kill
# until the process is provably gone. See CLAUDE.md "Stale running applications"
# + docs/install-sh-standard.md.
BUNDLE="$INSTALL_PATH"
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

if [ -d "$INSTALL_PATH" ]; then
    rm -rf "$INSTALL_PATH"
fi
# `ditto --noextattr` strips File Provider xattrs that break codesign
# when the project lives under iCloud-synced ~/Documents.
ditto --noextattr "$LOCAL_APP" "$INSTALL_PATH"

# ---- Relaunch a guaranteed-new instance + prove it's the new build ----
if [ "${NO_OPEN:-0}" -ne 0 ]; then
    echo "✅ ${APP_DISPLAY} installed to $INSTALL_PATH (not relaunched, --no-open)."
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
echo "✅ Verified: ${APP_DISPLAY} ${VER} running fresh (pid $FRESH_PID, started $START_STR)."
