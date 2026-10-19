#!/usr/bin/env bash
# Downloads the tiny test model used by native tests and verifies its hash.
#
# stories260K.gguf: a 260K parameter Llama trained on TinyStories, from
# karpathy/llama2.c (MIT), converted by the ggml-org team. About 1.2 MB.
set -euo pipefail
cd "$(dirname "$0")/.."
url="https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf"
sha="270cba1bd5109f42d03350f60406024560464db173c0e387d91f0426d3bd256d"
out="test/fixtures/stories260K.gguf"
mkdir -p "$(dirname "$out")"
if [ -f "$out" ] && echo "$sha  $out" | sha256sum -c --quiet 2>/dev/null; then
  echo "$out already present"; exit 0
fi
curl -fsSL --retry 3 -o "$out.part" "$url"
echo "$sha  $out.part" | sha256sum -c --quiet
mv "$out.part" "$out"
echo "Downloaded $out"
