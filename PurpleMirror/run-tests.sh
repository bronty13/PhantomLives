#!/usr/bin/env bash
# Runs PurpleMirror's unit tests (pure status-parsing logic). Adds
# Testing.framework paths for Command Line Tools setups (where `swift test`
# alone can't locate swift-testing). With full Xcode active, plain `swift test`
# works — this wrapper is harmless either way.
set -euo pipefail
cd "$(dirname "$0")"

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
INTEROP_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
        "$@"
else
    exec swift test "$@"
fi
