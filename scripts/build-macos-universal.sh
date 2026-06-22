#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
else
  SDK=$(xcrun --sdk macosx --show-sdk-path)
fi
export SDKROOT=$SDK

build_arch() {
  local arch=$1
  local scratch="$ROOT/.build-universal/$arch"
  export CLANG_MODULE_CACHE_PATH="$scratch/module-cache"
  export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/module-cache"
  mkdir -p "$scratch/module-cache" "$scratch/cache"
  swift build -c release --triple "$arch-apple-macosx13.0" --disable-sandbox \
    --package-path "$ROOT" --scratch-path "$scratch" --cache-path "$scratch/cache"
}

build_arch arm64
build_arch x86_64

APP="$ROOT/dist/FlashFlow-Universal.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  "$ROOT/.build-universal/arm64/arm64-apple-macosx/release/FlashFlow" \
  "$ROOT/.build-universal/x86_64/x86_64-apple-macosx/release/FlashFlow" \
  -output "$APP/Contents/MacOS/FlashFlow"
lipo -create \
  "$ROOT/.build-universal/arm64/arm64-apple-macosx/release/FlashFlowBridge" \
  "$ROOT/.build-universal/x86_64/x86_64-apple-macosx/release/FlashFlowBridge" \
  -output "$APP/Contents/MacOS/FlashFlowBridge"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Packaging/FlashFlow.icns" "$APP/Contents/Resources/FlashFlow.icns"
codesign --force --deep --sign - "$APP"
lipo -info "$APP/Contents/MacOS/FlashFlow"
echo "$APP"
