#!/usr/bin/env bash
# Builds the public GitHub release APK for the version in pubspec.yaml and
# puts it, named by version, in dist/vX.Y.Z/ with its SHA-256 sum:
#   emberwit-v1.2.3-arm64-v8a.apk
#   emberwit-v1.2.3-sha256sums.txt
#
# Only arm64-v8a: Emberwit needs a 64-bit phone. The benchmark model is
# bundled so the device check can run its speed test.
#
# Signing: the key described by ~/.emberwit-release/key.properties (or the
# file named by EMBERWIT_SIGNING). Without it this script stops, because a
# debug-signed APK can never be updated by a real release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION_LINE=$(grep -E '^version:' pubspec.yaml | head -1)
VERSION=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1/')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "pubspec.yaml version must look like 1.2.3+4, found: $VERSION_LINE" >&2; exit 1; }

SIGNING=${EMBERWIT_SIGNING:-$HOME/.emberwit-release/key.properties}
[ -f "$SIGNING" ] || { echo "No signing key at $SIGNING; refusing to build a debug-signed release." >&2; exit 1; }

tool/codegen.sh
tool/fetch_benchmark_model.sh
flutter build apk --release --flavor prod --target-platform android-arm64 \
  --obfuscate --split-debug-info="build/symbols/v$VERSION"

OUT="dist/v$VERSION"
rm -rf "$OUT"; mkdir -p "$OUT"
cp build/app/outputs/flutter-apk/app-prod-release.apk "$OUT/emberwit-v$VERSION-arm64-v8a.apk"
(cd "$OUT" && sha256sum ./*.apk | sed 's# \./# #' > "emberwit-v$VERSION-sha256sums.txt")
echo
echo "Built v$VERSION in $OUT (keep build/symbols/v$VERSION to read crash traces):"
ls -lh "$OUT"
