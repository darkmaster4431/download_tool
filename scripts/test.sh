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
swift build --disable-sandbox --package-path "$ROOT" --scratch-path "$ROOT/.build" --cache-path "$ROOT/.build/swiftpm-cache"
"$ROOT/.build/debug/FlashFlow" --self-test

jq empty "$ROOT/BrowserExtensions/Chrome/manifest.json" "$ROOT/BrowserExtensions/Safari/Resources/manifest.json"
node --check "$ROOT/BrowserExtensions/Chrome/service_worker.js"
node --check "$ROOT/BrowserExtensions/Chrome/popup.js"
node --check "$ROOT/BrowserExtensions/Safari/Resources/background.js"
node --check "$ROOT/BrowserExtensions/Safari/Resources/content.js"

rm -rf "$ROOT/.build/bridge-test-inbox"
node "$ROOT/Tests/bridge_test.js" "$ROOT/.build/debug/FlashFlowBridge" "$ROOT/.build/bridge-test-inbox"

swiftc -parse-as-library \
  "$ROOT/Sources/FlashFlow/Models.swift" \
  "$ROOT/Sources/FlashFlow/FileHasher.swift" \
  "$ROOT/Tests/HashIntegrationMain.swift" \
  -o "$ROOT/.build/hash-integration"
EXPECTED=$(shasum -a 256 "$ROOT/Tests/Fixtures/hash.txt" | cut -d ' ' -f 1)
"$ROOT/.build/hash-integration" "$ROOT/Tests/Fixtures/hash.txt" sha256 "$EXPECTED"

echo "All local checks passed"
