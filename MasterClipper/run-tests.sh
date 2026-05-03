#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Smoke test for MasterClipper — regenerates the Xcode project from project.yml
# and runs xcodebuild to verify the project still compiles. There are no real
# unit tests wired up yet; this script catches the most common regressions
# (missing imports, deleted symbols, broken project.yml).

# xcodebuild requires full Xcode (not Command Line Tools). Auto-fallback to
# /Applications/Xcode.app if xcode-select points at CLT.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "→ Regenerating Xcode project"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
else
    echo "  (xcodegen not on PATH — assuming the existing .xcodeproj is fresh)"
fi

echo "→ Building MasterClipper (Release)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

if xcodebuild \
       -project MasterClipper.xcodeproj \
       -scheme MasterClipper \
       -configuration Release \
       -derivedDataPath "$BUILD_DIR" \
       build \
       ONLY_ACTIVE_ARCH=YES 2>&1 \
   | grep -E "error:|warning:.*\.swift|\*\* BUILD" \
   | head -40; then
    :
fi

if [ -d "$BUILD_DIR/Build/Products/Release/MasterClipper.app" ]; then
    echo "✓ Build smoke test passed"
    exit 0
else
    echo "✗ Build failed — no MasterClipper.app produced"
    exit 1
fi
