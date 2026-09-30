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
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist")" = "10.15"
plutil -lint "$APP_DIR/Contents/Info.plist"

ICONSET="$ROOT_DIR/.build/MaosRec.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
test -s "$ICON_SOURCE"

while read -r name pixels; do
  sips -z "$pixels" "$pixels" "$ICON_SOURCE" --out "$ICONSET/$name" >/dev/null
  test -s "$ICONSET/$name"
done <<'ICON_SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
ICON_SIZES
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
test -s "$APP_DIR/Contents/Resources/AppIcon.icns"

BINARY="$APP_DIR/Contents/MacOS/MaosRec"
lipo "$BINARY" -verify_arch x86_64

binary_archs="$(lipo -archs "$BINARY")"
if [[ "$binary_archs" != "x86_64" ]]; then
  echo "Expected an Intel-only x86_64 binary, got: $binary_archs" >&2
  exit 1
fi

binary_min_os="$(otool -l "$BINARY" | awk '$1 == "minos" { print $2; exit }')"
case "$binary_min_os" in
  10.15|10.15.*) ;;
  *)
    echo "Expected macOS deployment target 10.15, got: ${binary_min_os:-unknown}" >&2
    exit 1
    ;;
esac

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT_DIR/dist/MaosRec-macOS-10.15-Intel.zip"

DMG_ROOT="$ROOT_DIR/.build/dmg-root"
DMG_MOUNT="/Volumes/Maos Record"
DMG_RW="$ROOT_DIR/.build/MaosRec-rw.dmg"
DMG_OUTPUT="$ROOT_DIR/dist/MaosRec-macOS-10.15-Intel.dmg"
rm -rf "$DMG_ROOT" "$DMG_RW" "$DMG_OUTPUT"
mkdir -p "$DMG_ROOT/.background"
cp -R "$APP_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$ROOT_DIR/Resources/DMGBackground.png" "$DMG_ROOT/.background/DMGBackground.png"

hdiutil create \
  -volname "Maos Record" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$DMG_RW"

DMG_DEVICE="$(
  hdiutil attach "$DMG_RW" \
    -readwrite \
    -noverify \
    -noautoopen |
    awk '/Apple_HFS/ { print $1; exit }'
)"
test -n "$DMG_DEVICE"
test -d "$DMG_MOUNT"

cleanup_dmg() {
  if [[ -n "${DMG_DEVICE:-}" ]]; then
    hdiutil detach "$DMG_DEVICE" >/dev/null 2>&1 || hdiutil detach -force "$DMG_DEVICE" >/dev/null 2>&1 || true
  fi
}

detach_dmg() {
  local attempt
  for attempt in 1 2 3; do
    if hdiutil detach "$DMG_DEVICE"; then
      return 0
    fi
    sleep 2
  done
  hdiutil detach -force "$DMG_DEVICE"
}

trap cleanup_dmg EXIT

osascript <<'APPLESCRIPT'
tell application "Finder"
  delay 1
  tell disk "Maos Record"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 780, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 14
    set background picture of viewOptions to file ".background:DMGBackground.png"
    set position of item "Maos Record.app" of container window to {165, 220}
    set position of item "Applications" of container window to {495, 220}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
detach_dmg
DMG_DEVICE=""
trap - EXIT

hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT"
rm -f "$DMG_RW"
test -s "$DMG_OUTPUT"

cd "$ROOT_DIR/dist"
shasum -a 256 MaosRec-macOS-10.15-Intel.zip MaosRec-macOS-10.15-Intel.dmg > SHA256SUMS.txt
