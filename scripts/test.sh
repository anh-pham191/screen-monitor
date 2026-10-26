#!/usr/bin/env bash
# Command Line Tools ship Swift Testing outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")/.."
# The flags below point at Command Line Tools; with Xcode selected, swift-testing versions clash.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
