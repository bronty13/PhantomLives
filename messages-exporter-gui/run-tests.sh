#!/usr/bin/env bash
# Runs the MessagesExporterGUI test suite. Adds Testing.framework paths
# for Command Line Tools setups (where `swift test` alone can't locate it).
# With full Xcode installed, plain `swift test` works without this wrapper.
set -euo pipefail

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
