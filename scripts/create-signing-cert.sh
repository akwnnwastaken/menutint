#!/usr/bin/env bash
# One-time setup: creates a self-signed code signing certificate called
# "MenuTint Self-Signed" in the login keychain. build-app.sh uses it when present,
# so every build has the same signature and macOS keeps the Screen Recording
# permission across rebuilds.
set -euo pipefail

NAME="MenuTint Self-Signed"

if security find-identity -p codesigning | grep "$NAME" >/dev/null; then
    echo "\"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout pass:menutint

security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P menutint -T /usr/bin/codesign

echo "Done: created \"$NAME\". ./scripts/build-app.sh will now sign with it."
