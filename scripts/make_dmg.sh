#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="1.1.0"
DMG_NAME="MacPulse-v${VERSION}-macOS.dmg"
ZIP_NAME="MacPulse-v${VERSION}-macOS.zip"
DIST_DIR="$ROOT/dist"
STAGING_DIR="$DIST_DIR/staging"

echo "1) Ensuring release app is built..."
if [ ! -d "/Applications/MacPulse.app" ]; then
    ./scripts/build_app.sh
fi

echo "2) Preparing distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

echo "3) Copying MacPulse.app to staging..."
cp -R "/Applications/MacPulse.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "4) Creating DMG..."
hdiutil create \
    -volname "MacPulse" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME"

echo "5) Creating ZIP archive..."
cd "$STAGING_DIR"
zip -r -y "$DIST_DIR/$ZIP_NAME" "MacPulse.app"
cd "$ROOT"

rm -rf "$STAGING_DIR"

echo "=== Generated Distribution Files ==="
ls -lh "$DIST_DIR"
