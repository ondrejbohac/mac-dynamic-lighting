#!/bin/zsh
# Packs build/Dynamic Lighting.app into build/DynamicLighting-<version>.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Dynamic Lighting.app"
DMG="build/DynamicLighting-${VERSION}.dmg"
STAGE="build/dmg"

[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Dynamic Lighting" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
