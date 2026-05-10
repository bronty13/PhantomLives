#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Runs the PurpleLifeTests bundle. Uses xcodebuild test, which requires full
# Xcode (not Command Line Tools). If xcode-select points at CLT but Xcode.app
# exists, use it.
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

echo "→ Running PurpleLifeTests"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

set +e
# Phase 4: override CODE_SIGN_ENTITLEMENTS to a no-iCloud variant for
# tests. Reason: CKContainer(identifier:) traps when the host doesn't
# carry the iCloud entitlement, AND the live iCloud entitlement makes
# the XCTest test runner hang at the connect-to-host phase. The
# no-iCloud override lets the test bundle inject cleanly; production
# builds via build-app.sh keep the full entitlement.
xcodebuild \
    -project PurpleLife.xcodeproj \
    -scheme PurpleLife \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    test \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_ENTITLEMENTS=Sources/PurpleLife/App/PurpleLife-NoCloud.entitlements 2>&1 \
  | grep -E "Test Case|error:|warning:.*\.swift|Executed|\*\* TEST" \
  | tail -80
status=${PIPESTATUS[0]}
set -e

if [ "$status" -eq 0 ]; then
    echo "✓ Tests passed"
    exit 0
else
    echo "✗ Tests failed (exit $status)"
    exit "$status"
fi
