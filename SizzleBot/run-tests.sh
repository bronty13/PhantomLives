#!/usr/bin/env bash
# SizzleBot test runner
# Usage: ./run-tests.sh
set -euo pipefail
cd "$(dirname "$0")"

log() { echo "[SizzleBot Tests] $*"; }

# Ensure the Xcode project is up to date
if ! command -v xcodegen &>/dev/null; then
    log "xcodegen not found — install with: brew install xcodegen"
    exit 1
fi

log "Regenerating Xcode project..."
xcodegen generate --quiet

log "Running tests..."
xcodebuild test \
    -project SizzleBot.xcodeproj \
    -scheme SizzleBot \
    -destination "platform=macOS" \
    -resultBundlePath /tmp/SizzleBotTestResults.xcresult \
    | xcpretty 2>/dev/null || \
xcodebuild test \
    -project SizzleBot.xcodeproj \
    -scheme SizzleBot \
    -destination "platform=macOS" \
    -resultBundlePath /tmp/SizzleBotTestResults.xcresult

log "Done. Results: /tmp/SizzleBotTestResults.xcresult"
