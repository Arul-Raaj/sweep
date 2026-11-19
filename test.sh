#!/bin/bash
# Runs the tests. With only Command Line Tools (no Xcode), SwiftPM doesn't find
# the Swift Testing macro plugin on its own, so point it there explicitly.
set -euo pipefail
cd "$(dirname "$0")"
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS"
else
    swift test
fi
