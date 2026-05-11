#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

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

echo "→ Running ElectronicDetectiveTests"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

set +e
xcodebuild \
    -project ElectronicDetective.xcodeproj \
    -scheme ElectronicDetective \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    test \
    ONLY_ACTIVE_ARCH=YES 2>&1 \
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
