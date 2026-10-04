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

# Ad-hoc signature so macOS can remember the Screen Recording permission.
codesign --force --sign - "$APP"

echo "Hazır: $APP"
