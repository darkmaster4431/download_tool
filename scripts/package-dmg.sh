#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
"$ROOT/scripts/build-app.sh"

STAGING="$ROOT/.build/dmg-root"
DMG="$ROOT/dist/FlashFlow.dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$ROOT/dist/FlashFlow.app" "$STAGING/FlashFlow.app"
cp -R "$ROOT/BrowserExtensions/Chrome" "$STAGING/FlashFlow-Chrome-Extension"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "FlashFlow" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --verify --deep --strict "$ROOT/dist/FlashFlow.app"
hdiutil verify "$DMG"
echo "$DMG"
