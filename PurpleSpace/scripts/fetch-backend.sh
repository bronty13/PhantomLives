#!/bin/bash
# Stage the pinned convex-local-backend binary into resources/.
#
# The binary is the open-source Convex backend (FSL license). It is NOT
# downloaded directly: the official `convex` npm CLI provisions and caches
# it (~/.cache/convex/binaries/<tag>/) via its documented anonymous
# local-dev mode, and this script copies the pinned tag out of that cache.
# electron-builder then packs resources/ into the .app via extraResources,
# so the installed app is fully self-contained (no account, no docker).
#
# Re-run after bumping BACKEND_TAG; it no-ops when already current.
set -euo pipefail

cd "$(dirname "$0")/.."

# Keep in sync with src/main/convexBackend.ts (BACKEND_TAG).
BACKEND_TAG="precompiled-2026-06-09-b6aaa1a"

CACHE="$HOME/.cache/convex/binaries/${BACKEND_TAG}/convex-local-backend"
DEST_DIR="resources"
DEST="${DEST_DIR}/convex-local-backend"
TAG_FILE="${DEST_DIR}/.backend-tag"

if [ -x "$DEST" ] && [ -f "$TAG_FILE" ] && [ "$(cat "$TAG_FILE")" = "$BACKEND_TAG" ]; then
    echo "convex-local-backend ${BACKEND_TAG} already staged."
    exit 0
fi

if [ ! -x "$CACHE" ]; then
    echo "Provisioning backend binary via the convex CLI (anonymous local dev)..."
    CONVEX_AGENT_MODE=anonymous npx convex dev --once >/dev/null
fi
if [ ! -x "$CACHE" ]; then
    echo "error: convex CLI did not cache ${BACKEND_TAG}." >&2
    echo "       Cached tags: $(ls "$HOME/.cache/convex/binaries" 2>/dev/null | tr '\n' ' ')" >&2
    echo "       If the CLI now recommends a newer tag, bump BACKEND_TAG here and in src/main/convexBackend.ts." >&2
    exit 1
fi

mkdir -p "$DEST_DIR"
cp "$CACHE" "$DEST"
chmod +x "$DEST"
echo "$BACKEND_TAG" > "$TAG_FILE"
echo "Staged ${DEST} (${BACKEND_TAG}, $(du -h "$DEST" | cut -f1 | tr -d ' '))."
