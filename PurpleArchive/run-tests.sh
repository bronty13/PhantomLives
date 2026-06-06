#!/usr/bin/env bash
#
# run-tests.sh — run the ArchiveKit test suite.
#
# `swift test` needs the XCTest framework, which only ships with a full Xcode
# install — under a Command Line Tools toolchain it errors "no such module
# 'XCTest'". So we point DEVELOPER_DIR at a full Xcode when xcode-select is on
# the CLT, then run the SwiftPM tests.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DEV="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV" != *"/Xcode"*".app/"* ]]; then
  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    if [[ -d "$candidate" ]]; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      echo "▸ Using full Xcode at $candidate (CLT lacks XCTest)"
      break
    fi
  done
fi

echo "▸ swift test"
swift test "$@"
