#!/usr/bin/env bash
set -euo pipefail

TAG=b12110
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/llama-$TAG"
TARGET="$ROOT/Vendor/llama.xcframework"

if [[ -f "$TARGET/.tag" && "$(cat "$TARGET/.tag")" == "$TAG" ]]; then
    echo "llama.xcframework $TAG is ready"
    exit 0
fi

command -v cmake >/dev/null || { echo "Install CMake first: brew install cmake" >&2; exit 1; }

if [[ ! -d "$SOURCE" ]]; then
    git clone --quiet --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$SOURCE"
fi

cd "$SOURCE"
./build-xcframework.sh ios-sim ios-device

rm -rf "$TARGET"
mkdir -p "$ROOT/Vendor"
cp -R build-apple/llama.xcframework "$TARGET"
echo "$TAG" > "$TARGET/.tag"
echo "llama.xcframework $TAG is ready"
