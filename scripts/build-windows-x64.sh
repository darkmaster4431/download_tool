#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
if [[ -x "$ROOT/.tools/go-toolchain/bin/go" ]]; then
  GO="$ROOT/.tools/go-toolchain/bin/go"
else
  GO=$(command -v go)
fi
mkdir -p "$ROOT/dist/windows"
mkdir -p "$ROOT/.build/go-cache" "$ROOT/.build/go-mod-cache"
cd "$ROOT/Windows"
GOCACHE="$ROOT/.build/go-cache" GOMODCACHE="$ROOT/.build/go-mod-cache" \
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 "$GO" build -trimpath -ldflags "-H windowsgui -s -w" \
  -o "$ROOT/dist/windows/FlashFlow-Windows-x64.exe" .
file "$ROOT/dist/windows/FlashFlow-Windows-x64.exe"
echo "$ROOT/dist/windows/FlashFlow-Windows-x64.exe"
