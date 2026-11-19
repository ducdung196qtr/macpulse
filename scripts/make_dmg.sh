#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RAW_VER="${1:-${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || echo "1.1.1")}}"
VERSION="${RAW_VER#v}"
DMG_NAME="MacPulse-v${VERSION}-macOS.dmg"
ZIP_NAME="MacPulse-v${VERSION}-macOS.zip"
DIST_DIR="$ROOT/dist"
STAGING_DIR="$DIST_DIR/staging"

echo "1) Ensuring release app is built..."
APP_SRC="${APP_BUNDLE:-/Applications/MacPulse.app}"
if [ ! -d "$APP_SRC" ]; then
    APP_SRC="$ROOT/build/MacPulse.app"
    if [ ! -d "$APP_SRC" ]; then
        APP_BUNDLE="$APP_SRC" ./scripts/build_app.sh
    fi
fi

echo "2) Preparing distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

echo "3) Copying $APP_SRC to staging..."
cp -R "$APP_SRC" "$STAGING_DIR/MacPulse.app"
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
