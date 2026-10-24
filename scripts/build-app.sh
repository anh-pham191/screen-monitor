#!/usr/bin/env bash
# Builds LG Control.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product LGControl
BIN="$(swift build -c release --show-bin-path)/LGControl"

APP=".build/LG Control.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/LGControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signing: enough for SMAppService and a stable bundle, no certificate needed.
codesign --force --sign - "$APP"

pkill -x LGControl || true
mkdir -p ~/Applications
DEST="$HOME/Applications/LG Control.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "$DEST"
