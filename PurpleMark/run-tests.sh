#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

xcodebuild test \
    -project PurpleMark.xcodeproj \
    -scheme PurpleMark \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/pm-test-dd \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E "Test Suite|Test Case|passed|failed|error:|BUILD (SUCCEEDED|FAILED)" \
    | grep -vE "prebuilt-modules" || true
