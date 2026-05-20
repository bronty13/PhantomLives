#!/usr/bin/env bash
# build-app.sh — build the macOS Molly.app bundle via Tauri, then chain
# into install.sh to drop the result into /Applications/.
#
# Usage:
#   ./build-app.sh                # build + install + relaunch
#   ./build-app.sh --no-open      # build + install, no focus steal
#   ./build-app.sh --no-install   # build only (legacy behaviour)
#   BUILD_ONLY=1 ./build-app.sh   # same, via env
#
# For Windows builds, push a `v*` tag and let .github/workflows/release.yml
# do the cross-build — Tauri's Mac→Windows cross-compile is brittle.

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

# Make sure node_modules is in sync.
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

# Build the Tauri bundle.
pnpm tauri build "$@"

# Chain into install.sh (per PhantomLives standard). Honor escape hatches.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    if [ -x "$PROJECT_DIR/install.sh" ]; then
        "$PROJECT_DIR/install.sh" $INSTALL_FLAGS
    fi
fi
