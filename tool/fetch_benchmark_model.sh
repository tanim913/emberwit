#!/usr/bin/env bash
# Downloads the micro benchmark model bundled with the app and verifies it.
#
# SmolLM2-135M-Instruct, Q4_0 GGUF (91.9 MB), Apache-2.0, by Hugging Face
# (HuggingFaceTB), converted by bartowski. Under the 100 MB budget and fast
# to load, so the speed test finishes in about 10 seconds even on low end
# phones. Release builds must run this first; without it the app still works
# and the speed test reports that it is not available.
set -euo pipefail
cd "$(dirname "$0")/.."
url="https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_0.gguf"
sha="bcc3af2849ad6095af57e9b5cd43775256efdc66e306acb529172f92d0c04b03"
out="assets/models/benchmark.gguf"
if [ -f "$out" ] && echo "$sha  $out" | sha256sum -c --quiet 2>/dev/null; then
  echo "$out already present"; exit 0
fi
curl -fsSL --retry 3 -o "$out.part" "$url"
echo "$sha  $out.part" | sha256sum -c --quiet
mv "$out.part" "$out"
echo "Downloaded $out"
