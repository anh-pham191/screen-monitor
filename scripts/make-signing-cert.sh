#!/usr/bin/env bash
# One-time: create a self-signed code-signing identity "LG Control Local Signing" in the login
# keychain so Accessibility permission survives rebuilds. Prompts for your password once or twice.
set -euo pipefail

NAME="LG Control Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Signing identity '$NAME' already exists; nothing to do."
  exit 0
fi

# LibreSSL only: Homebrew OpenSSL 3 writes .p12 files that `security import` rejects.
OPENSSL=/usr/bin/openssl
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(/usr/bin/openssl rand -hex 16)"

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=$NAME" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "keyUsage=digitalSignature" \
  -addext "basicConstraints=CA:false"

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$PASS" -name "$NAME"

security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

# Trust the certificate for code signing (prompts for your password).
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

# Let codesign use the key without a prompt on every build (prompts once).
# Scoped by label (-l, set by -name on the .p12 above) to this key only: without it, the command
# rewrites the partition list of every private key in the login keychain, changing which apps
# may use Anh's other signing keys without asking.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" "$KEYCHAIN"

echo "Created signing identity '$NAME'. scripts/build-app.sh will now use it."
