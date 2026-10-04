#!/usr/bin/env bash
# Builds build/MenuTint.app (universal: Apple Silicon + Intel).
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH_FLAGS=(--arch arm64 --arch x86_64)
if [[ "${1:-}" == "--native" ]]; then
    ARCH_FLAGS=()
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/MenuTint.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MenuTint" "$APP/Contents/MacOS/MenuTint"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# With a stable identity (see create-signing-cert.sh) macOS keeps the Screen
# Recording permission across rebuilds; an ad-hoc signature changes every build.
IDENTITY="MenuTint Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep "$IDENTITY" >/dev/null; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
    echo "Not: Ekran Kaydı izninin her derlemede sıfırlanmaması için bir kez ./scripts/create-signing-cert.sh çalıştır."
fi

echo "Hazır: $APP"
