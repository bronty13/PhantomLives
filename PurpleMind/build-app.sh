#!/usr/bin/env bash
# build-app.sh — build the macOS PurpleMind.app bundle via Tauri, then
# chain into install.sh to drop it into /Applications/.
#
# Usage:
#   ./build-app.sh                # build + install + relaunch
#   ./build-app.sh --no-open      # build + install, no focus steal
#   ./build-app.sh --no-install   # build only
#   BUILD_ONLY=1 ./build-app.sh   # same, via env
#
# Windows builds come from CI on a purplemind-v* tag (see
# .github/workflows/release-purplemind.yml).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

if ! command -v pnpm >/dev/null 2>&1; then
  echo "❌ pnpm not found. Install with: brew install pnpm"
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "❌ cargo not found. Install Rust with: brew install rust"
  exit 1
fi

pnpm install --frozen-lockfile 2>/dev/null || pnpm install

# Force a fresh frontend build every time — `tsc -b` is incremental and
# `vite build` honors the .vite cache, which has bitten SideMolly twice with
# newly-edited TSX silently not making it into the .app bundle (the Rust side
# rebuilds fine; the React side stays stale). Wiping dist/ plus the tsc
# buildinfo is cheap and the `beforeBuildCommand` hook regenerates everything.
rm -rf "$PROJECT_DIR/dist"
rm -f  "$PROJECT_DIR/tsconfig.tsbuildinfo"

# Strip --no-install / --no-open before forwarding the rest to Tauri.
TAURI_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-open|--no-install) ;;
        *) TAURI_ARGS+=("$arg") ;;
    esac
done

pnpm tauri build ${TAURI_ARGS[@]+"${TAURI_ARGS[@]}"}

if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    if [ -x "$PROJECT_DIR/install.sh" ]; then
        "$PROJECT_DIR/install.sh" $INSTALL_FLAGS
    fi
fi
