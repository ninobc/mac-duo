#!/usr/bin/env bash
#
# Builds "Mac Duo.app" from the Swift package.
#
#   Scripts/build.sh                 release build, ad-hoc signed
#   Scripts/build.sh --run           …and launch it
#   Scripts/build.sh --universal     Apple silicon + Intel
#   Scripts/build.sh --debug         debug configuration
#
# Environment:
#   SIGN_IDENTITY   codesign identity (default "-", ad-hoc). Use a
#                   "Developer ID Application: …" identity for distribution.
#   APP_VERSION     override CFBundleShortVersionString
#   BUILD_NUMBER    override CFBundleVersion

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Mac Duo"
BUNDLE="build/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CONFIG=release
RUN=false
BUILD_ARGS=()

for argument in "$@"; do
  case "$argument" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --run) RUN=true ;;
    --debug) CONFIG=debug ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done
BUILD_ARGS+=(-c "$CONFIG")

swift build "${BUILD_ARGS[@]}" --product MacDuo
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH/MacDuo" "$BUNDLE/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
[ -f Resources/Assets.car ] && cp Resources/Assets.car "$BUNDLE/Contents/Resources/Assets.car"
cp LICENSE "$BUNDLE/Contents/Resources/LICENSE" 2>/dev/null || true
echo -n "APPL????" > "$BUNDLE/Contents/PkgInfo"

if [ -n "${APP_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$BUNDLE/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$BUNDLE/Contents/Info.plist"
fi

TIMESTAMP=(--timestamp)
if [[ "$SIGN_IDENTITY" == "-" ]]; then TIMESTAMP=(--timestamp=none); fi
codesign --force --options runtime "${TIMESTAMP[@]}" \
  --entitlements Resources/MacDuo.entitlements \
  --sign "$SIGN_IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"
echo "built $BUNDLE"

if $RUN; then
  pkill -x MacDuo 2>/dev/null || true
  sleep 0.4
  open "$BUNDLE"
  echo "launched"
fi
