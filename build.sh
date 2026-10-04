#!/bin/bash
# Compila RainDesktop como app universal, la firma y la instala en ~/Applications.
#   ./build.sh               compila, instala y abre
#   ./build.sh --no-install  solo compila en build/RainDesktop.app
set -euo pipefail
cd "$(dirname "$0")"

APP=RainDesktop
BUILD=build
BUNDLE="$BUILD/$APP.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
MIN_MACOS=14.0

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

for arch in arm64 x86_64; do
    echo "→ Compilando $arch"
    swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" \
        Sources/*.swift -o "$BUILD/$APP-$arch"
done
lipo -create "$BUILD/$APP-arm64" "$BUILD/$APP-x86_64" -output "$BUNDLE/Contents/MacOS/$APP"
rm "$BUILD/$APP-arm64" "$BUILD/$APP-x86_64"
cp Info.plist "$BUNDLE/Contents/Info.plist"

echo "→ Firmando"
codesign --force --sign - --options runtime --entitlements "$APP.entitlements" "$BUNDLE"
codesign --verify --strict --verbose=2 "$BUNDLE"

if [[ "${1:-}" == "--no-install" ]]; then
    echo "✓ $BUNDLE"
    exit 0
fi

echo "→ Instalando en $INSTALL_DIR"
if pgrep -x "$APP" >/dev/null; then
    pkill -x "$APP" || true
    for _ in {1..50}; do pgrep -x "$APP" >/dev/null || break; sleep 0.1; done
fi
mkdir -p "$INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/$APP.app"
ditto "$BUNDLE" "$INSTALL_DIR/$APP.app"
open "$INSTALL_DIR/$APP.app"
echo "✓ $INSTALL_DIR/$APP.app"
