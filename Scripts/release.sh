#!/usr/bin/env bash
#
# Full release: universal build, sign, package, (notarize), write site/updates.json.
#
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=macduo Scripts/release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
export APP_VERSION="$VERSION" BUILD_NUMBER
Scripts/make-icon.sh
Scripts/build.sh --universal
Scripts/package-dmg.sh
SITE="${SITE_DIR:-../mac-duo-site}"
if [ -d "$SITE/public" ]; then
cat > "$SITE/public/updates.json" <<JSON
{
  "version": "$VERSION",
  "url": "https://mac-duo.com/#install",
  "notes": "Mac Duo $VERSION is available. Download it from mac-duo.com."
}
JSON
echo "updated $SITE/public/updates.json"
fi
echo "release $VERSION ready in dist/"
