#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
else
  SDK=$(xcrun --sdk macosx --show-sdk-path)
fi
export SDKROOT=$SDK
export CLANG_MODULE_CACHE_PATH=$ROOT/.build/module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=$ROOT/.build/module-cache

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$ROOT/.build/swiftpm-cache"
swift build -c release --disable-sandbox --package-path "$ROOT" --scratch-path "$ROOT/.build" --cache-path "$ROOT/.build/swiftpm-cache"

APP="$ROOT/dist/FlashFlow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/FlashFlow" "$APP/Contents/MacOS/FlashFlow"
cp "$ROOT/.build/release/FlashFlowBridge" "$APP/Contents/MacOS/FlashFlowBridge"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Packaging/FlashFlow.icns" "$APP/Contents/Resources/FlashFlow.icns"
rm -rf "$APP/Contents/Resources/ChromeExtension"
cp -R "$ROOT/BrowserExtensions/Chrome" "$APP/Contents/Resources/ChromeExtension"
codesign --force --deep --sign - "$APP"
echo "$APP"
