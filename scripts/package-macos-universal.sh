#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
"$ROOT/scripts/build-macos-universal.sh"

STAGING="$ROOT/.build-universal/dmg-root"
DMG="$ROOT/dist/FlashFlow-macOS-Universal.dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$ROOT/dist/FlashFlow-Universal.app" "$STAGING/FlashFlow.app"
cp -R "$ROOT/BrowserExtensions/Chrome" "$STAGING/FlashFlow-Chrome-Extension"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "FlashFlow Universal" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --verify --deep --strict "$STAGING/FlashFlow.app"
hdiutil verify "$DMG"
echo "$DMG"
