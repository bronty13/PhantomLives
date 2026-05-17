#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Prefer full Xcode over Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

DERIVED="$(mktemp -d)"
xcodebuild test \
    -project PurpleReel.xcodeproj \
    -scheme PurpleReel \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED/DerivedData" \
    -allowProvisioningUpdates \
    | grep -E "Test Suite|error:|warning:|FAILED|passed|failed" \
    | grep -vE "ChildAccountControl|^xcodebuild" || true
