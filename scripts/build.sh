#!/bin/bash
# Build Glide into an ad-hoc-signed .app bundle without Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Glide.app"
ICONSET="$ROOT/build/AppIcon.iconset"
SRC="$ROOT/design/AppIcon.appiconset"

echo "▸ Compiling ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Glide"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glide"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "▸ Building icon…"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp "$SRC/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$SRC/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$SRC/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$SRC/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$SRC/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$SRC/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$SRC/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$SRC/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$SRC/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$SRC/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -p codesigning 2>/dev/null | grep -q "Glide Dev"; then
    echo "▸ Signing (Glide Dev — stable identity)…"
    codesign --force --deep --sign "Glide Dev" "$APP" >/dev/null 2>&1
else
    echo "▸ Signing (ad-hoc — run scripts/setup-signing.sh for mic/speech prompts)…"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1
fi

echo "✓ Built $APP"
