#!/usr/bin/env bash
# Renders the app icon and packs Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/icon
if [ -f Resources/IconArt/mark.png ]; then
  # The rendered artwork, fitted to the macOS icon grid.
  swift Scripts/icon/MaskIcon.swift Resources/IconArt/mark.png build/icon/AppIcon-1024.png
else
  # Procedural fallback.
  swift Scripts/icon/MakeIcon.swift build/icon/AppIcon-1024.png
fi
ICONSET=build/icon/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d build/icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp build/icon/AppIcon-1024.png site/assets/icon-1024.png 2>/dev/null || true
echo "wrote Resources/AppIcon.icns"
