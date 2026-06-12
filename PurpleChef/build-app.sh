#!/bin/bash
# Build Purple Chef.app for the host architecture and (by default) install
# it into /Applications + relaunch.
#
# Usage:
#     ./build-app.sh                       # build + install + relaunch
#     ./build-app.sh --no-open             # build + install, skip relaunch
#     ./build-app.sh --no-install          # build only, leave under dist/
#     BUILD_ONLY=1 ./build-app.sh          # same, via env (CI / signature checks)
#
# For a signed universal2 release DMG, use `npm run dist:mac`. This root
# script is the PhantomLives-convention fast-iteration path: host-arch
# only, no DMG, no signing dance.
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d node_modules ]; then
    echo "==> Installing npm dependencies (first run)"
    npm install --silent
fi

echo "==> Type-checking + bundling renderer/main/preload"
npm run build

APP_NAME="Purple Chef"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Packaging .app (host arch, no dmg, no sign)"
# --dir produces an unpacked .app without a .dmg / signing dance.
npx electron-builder --mac --dir --config.mac.identity=null --config.mac.target=dir

# Sanity: confirm the bundle landed somewhere we recognize.
FOUND=""
for d in "dist/mac-arm64" "dist/mac" "dist/mac-x64" "dist/mac-universal"; do
    if [ -d "$d/$APP_BUNDLE" ]; then
        FOUND="$PWD/$d/$APP_BUNDLE"
        break
    fi
done
if [ -z "$FOUND" ]; then
    echo "error: built .app not found under dist/" >&2
    ls -la dist/ 2>/dev/null || true
    exit 1
fi
echo "    built: $FOUND"

# Auto-install: replace /Applications/Purple Chef.app and relaunch. Opt
# out with `--no-install` (CI builds, signature inspection) or
# `--no-open` (install without focus-stealing relaunch). Per the root
# CLAUDE.md install.sh standard.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    if [ -x "$(dirname "$0")/install.sh" ]; then
        "$(dirname "$0")/install.sh" $INSTALL_FLAGS
    fi
fi
