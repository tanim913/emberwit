#!/usr/bin/env bash
# Downloads the pinned llama.cpp xcframework for CocoaPods builds and checks
# its sha256. Swift Package Manager builds do not need this.
set -euo pipefail
cd "$(dirname "$0")"
tag="b11155"
sha="1f157b625fe298aba099572a90aade102a1de31769ddfeff0e08330fb1296979"
zip="llama-$tag-xcframework.zip"
[ -d Frameworks/llama.xcframework ] && { echo "already present"; exit 0; }
curl -fsSL --retry 3 -o "$zip" "https://github.com/ggml-org/llama.cpp/releases/download/$tag/$zip"
echo "$sha  $zip" | shasum -a 256 -c -
mkdir -p Frameworks
unzip -q "$zip" -d Frameworks.tmp
mv "$(find Frameworks.tmp -name llama.xcframework -type d | head -1)" Frameworks/
rm -rf Frameworks.tmp "$zip"
