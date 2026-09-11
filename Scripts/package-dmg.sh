#!/usr/bin/env bash
#
# Packages build/Mac Duo.app into dist/Mac-Duo-<version>.dmg and .zip.
#
#   Scripts/package-dmg.sh
#
# Environment:
#   SIGN_IDENTITY    identity for signing the DMG (default: none)
#   NOTARY_PROFILE   notarytool keychain profile; when set, the DMG is
#                    notarized and stapled (needs a Developer ID identity).

set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Mac Duo.app"
[ -d "$APP" ] || { echo "build the app first: Scripts/build.sh" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p dist
DMG="dist/Mac-Duo-${VERSION}.dmg"
ZIP="dist/Mac-Duo-${VERSION}.zip"
rm -f "$DMG" "$ZIP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Mac Duo.app"
ln -s /Applications "$STAGING/Applications"

if command -v create-dmg >/dev/null 2>&1 && [ -f Resources/dmg-background.png ]; then
  create-dmg \
    --volname "Mac Duo" \
    --volicon "Resources/AppIcon.icns" \
    --background "Resources/dmg-background.png" \
    --window-pos 200 120 --window-size 660 420 \
    --icon-size 128 \
    --icon "Mac Duo.app" 180 200 \
    --app-drop-link 480 200 \
    --no-internet-enable \
    "$DMG" "$STAGING" >/dev/null
else
  hdiutil create -volname "Mac Duo" -srcfolder "$STAGING" -fs HFS+ -format UDZO -quiet "$DMG"
fi

if [ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# Version-less copies, so /releases/latest/download/Mac-Duo.dmg always works.
cp "$DMG" dist/Mac-Duo.dmg
cp "$ZIP" dist/Mac-Duo.zip
shasum -a 256 "$DMG" "$ZIP" | tee dist/SHA256SUMS.txt
echo "packaged $DMG and $ZIP"
