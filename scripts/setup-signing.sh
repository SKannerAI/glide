#!/bin/bash
# Create a stable, self-signed code-signing identity ("Glide Dev") so macOS TCC
# will prompt for and remember microphone/speech permission across rebuilds.
# Uses a dedicated keychain so your login keychain and its password aren't touched.
set -euo pipefail

IDENTITY="Glide Dev"
KC="$HOME/Library/Keychains/glide-signing.keychain-db"
KCPW="glide-local-signing"
WORK="$HOME/.glide-signing"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ Signing identity '$IDENTITY' already exists."
    exit 0
fi

echo "▸ Generating self-signed code-signing certificate…"
mkdir -p "$WORK"; cd "$WORK"
cat > openssl.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes -config openssl.cnf >/dev/null 2>&1

echo "▸ Creating dedicated signing keychain…"
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"                    # no auto-lock
security unlock-keychain -p "$KCPW" "$KC"
# Import cert + key as separate PEMs (avoids OpenSSL-3 PKCS12 MAC incompatibility
# with Apple's Security framework).
security import cert.pem -k "$KC" -T /usr/bin/codesign -A
security import key.pem -k "$KC" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null 2>&1
# Prepend our keychain to the user search list, preserving the rest.
EXISTING=$(security list-keychains -d user | sed 's/[",]//g')
security list-keychains -d user -s "$KC" $EXISTING >/dev/null 2>&1

rm -f key.pem cert.pem openssl.cnf
echo "✓ Done. Identities available to codesign:"
security find-identity -v -p codesigning | grep "$IDENTITY" || echo "  (identity not found — check errors above)"
