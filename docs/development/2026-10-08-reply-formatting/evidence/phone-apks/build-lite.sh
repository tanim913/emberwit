#!/usr/bin/env bash
# Build a phone-sized test APK with the same benchmark omission as the old lite APK.
# All runtime source, dependencies and platform configuration are preserved.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../../../../.." && pwd)"
cd "$project_root"
artifact="build/emberwit-0.1.0-arm64-lite-20261008.apk"
evidence="docs/development/2026-10-08-reply-formatting/evidence/phone-apks"
benchmark_hold="$(mktemp -d /tmp/emberwit-lite-benchmark.XXXXXX)"
restore_benchmark() {
  if [ -f "$benchmark_hold/benchmark.gguf" ]; then
    mv "$benchmark_hold/benchmark.gguf" assets/models/benchmark.gguf
  fi
  if [ -d "$benchmark_hold" ]; then rmdir "$benchmark_hold"; fi
}
trap restore_benchmark EXIT
if [ -f assets/models/benchmark.gguf ]; then
  mv assets/models/benchmark.gguf "$benchmark_hold/benchmark.gguf"
fi
flutter build apk --release --flavor prod \
  --target-platform android-arm64 --obfuscate \
  --split-debug-info=build/symbols/prod-phone-lite-20261008 \
  > "$evidence/lite-build.log" 2>&1
cp build/app/outputs/flutter-apk/app-prod-release.apk "$artifact"
