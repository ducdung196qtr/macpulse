#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "1) Running unit tests..."
swift run MacPulseTests

echo "2) Building release binary..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/MacPulse"
APP_BUNDLE="${APP_BUNDLE:-/Applications/MacPulse.app}"

echo "3) Generating AppIcon.icns..."
swift scripts/make_icon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
rm -rf Resources/AppIcon.iconset

echo "4) Assembling $APP_BUNDLE..."
pkill -x MacPulse 2>/dev/null || true
sleep 0.4
# Do NOT rm -rf $APP_BUNDLE to preserve macOS TCC Accessibility permissions and bundle inode
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp -f "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/MacPulse"
cp -f Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp -f Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$APP_BUNDLE/Contents/MacOS/MacPulse"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

echo "5) Ad-hoc signing $APP_BUNDLE with persistent designated requirement..."
# Preserving bundle identifier in designated requirement avoids TCC Accessibility permission reset on rebuilds
codesign --force --deep -s - --requirements '=designated => identifier "com.ducdung.MacPulse"' "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE"
codesign -d -r- "$APP_BUNDLE"

echo "Done! Installed at $APP_BUNDLE"
