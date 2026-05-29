#!/bin/bash
# Reinstall the freshly-built PurpleVoice.app into /Applications/, then
# install a `purplevoice` shell wrapper into a writable PATH entry so
# the CLI mode is reachable as `purplevoice clean foo.m4a`.
#
# Usage:
#     ./install.sh             # quit running, replace, install CLI, relaunch
#     ./install.sh --no-open   # quit running, replace, install CLI, don't relaunch
#     ./install.sh --no-cli    # skip the CLI wrapper install
set -euo pipefail

cd "$(dirname "$0")"

SRC="$PWD/PurpleVoice.app"
DST="/Applications/PurpleVoice.app"
OPEN_AFTER=1
INSTALL_CLI=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        --no-cli)  INSTALL_CLI=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo "error: $SRC does not exist. Run ./build-app.sh first." >&2
    exit 1
fi

echo "Quitting any running PurpleVoice..."
osascript -e 'tell application "PurpleVoice" to quit' >/dev/null 2>&1 || true
sleep 1

if [ -d "$DST" ]; then
    echo "Removing existing $DST"
    rm -rf "$DST"
fi

echo "Copying $SRC → $DST"
ditto --noextattr "$SRC" "$DST"

if [ "$INSTALL_CLI" -eq 1 ]; then
    # Pick the first writable PATH-resident directory in priority order.
    # Apple Silicon Homebrew (/opt/homebrew/bin) wins on most dev Macs;
    # /usr/local/bin works on Intel; ~/.local/bin is the no-sudo fallback.
    WRAPPER_DIR=""
    for cand in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [ -d "$cand" ] && [ -w "$cand" ]; then
            WRAPPER_DIR="$cand"
            break
        fi
    done
    if [ -z "$WRAPPER_DIR" ]; then
        mkdir -p "$HOME/.local/bin"
        WRAPPER_DIR="$HOME/.local/bin"
        echo "note: created $WRAPPER_DIR — add it to your PATH if it isn't already" >&2
    fi
    WRAPPER="$WRAPPER_DIR/purplevoice"
    cat > "$WRAPPER" <<'WRAP'
#!/bin/bash
# PurpleVoice CLI wrapper. The same binary inside the .app handles
# both GUI and CLI modes; routing happens in MainEntry.swift based on
# argv[1]. Installed by PurpleVoice/install.sh.
exec "/Applications/PurpleVoice.app/Contents/MacOS/PurpleVoice" "$@"
WRAP
    chmod +x "$WRAPPER"
    echo "Installed CLI wrapper: $WRAPPER"
fi

if [ "$OPEN_AFTER" -eq 1 ]; then
    echo "Launching $DST"
    open "$DST"
else
    echo "Skipping launch (--no-open)."
fi
