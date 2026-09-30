#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
GITHUB_REPOSITORY_SLUG="${GITHUB_REPOSITORY:-noneandundefined/MaosRec}"

cd "$ROOT_DIR"
MACOSX_DEPLOYMENT_TARGET=10.15 swift build -c release --arch x86_64
BIN_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"

APP_DIR="$ROOT_DIR/dist/Maos Record.app"
rm -rf "$ROOT_DIR/dist"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/MaosRec" "$APP_DIR/Contents/MacOS/MaosRec"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"
cp -R "$ROOT_DIR/Resources/en.lproj" "$APP_DIR/Contents/Resources/"
cp -R "$ROOT_DIR/Resources/ru.lproj" "$APP_DIR/Contents/Resources/"
chmod 755 "$APP_DIR/Contents/MacOS/MaosRec"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :MaosRecGitHubRepository $GITHUB_REPOSITORY_SLUG" "$APP_DIR/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" = "$APP_VERSION"
plutil -lint "$APP_DIR/Contents/Info.plist"

ICONSET="$ROOT_DIR/.build/MaosRec.iconset"
rm -rf "$ICONSET"
swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICONSET"
for icon in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png; do
  test -s "$ICONSET/$icon"
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
test -s "$APP_DIR/Contents/Resources/AppIcon.icns"

lipo "$APP_DIR/Contents/MacOS/MaosRec" -verify_arch x86_64
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT_DIR/dist/MaosRec-macOS-10.15-Intel.zip"

DMG_ROOT="$ROOT_DIR/.build/dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Maos Record" -srcfolder "$DMG_ROOT" -ov -format UDZO "$ROOT_DIR/dist/MaosRec-macOS-10.15-Intel.dmg"

cd "$ROOT_DIR/dist"
shasum -a 256 MaosRec-macOS-10.15-Intel.zip MaosRec-macOS-10.15-Intel.dmg > SHA256SUMS.txt
