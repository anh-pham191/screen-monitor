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

# Accessibility (and Launch at login) is tied to the code signature, and an ad-hoc signature
# changes on every build. The local certificate from make-signing-cert.sh keeps it stable.
# Sign by SHA-1 hash, not name, so a duplicate certificate with the same name isn't ambiguous.
# Captured first and matched with a here-string: no pipe, so no SIGPIPE under pipefail.
IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
HASH="$(awk '/"LG Control Local Signing"/ && !found { print $2; found = 1 }' <<<"$IDENTITIES")"
if [[ -n "$HASH" ]]; then
    codesign --force --timestamp=none --sign "$HASH" "$APP"
else
    codesign --force --sign - "$APP"
    echo "warning: ad-hoc signed; Accessibility permission will reset on every build — run scripts/make-signing-cert.sh once" >&2
fi

pkill -x LGControl || true
mkdir -p ~/Applications
DEST="$HOME/Applications/LG Control.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "$DEST"
