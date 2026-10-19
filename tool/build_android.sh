#!/usr/bin/env bash
# Builds an Android release artifact for one flavor.
#
# Usage: tool/build_android.sh <dev|staging|prod> [apk|appbundle]
#
# Release builds are always obfuscated; symbols go to build/symbols/<flavor>
# and must be kept to decode stack traces. Only arm64-v8a and x86_64 are
# built: the Flutter CLI ignores Gradle abiFilters, so pass them here.
set -euo pipefail
cd "$(dirname "$0")/.."
flavor="${1:?flavor required: dev, staging or prod}"
artifact="${2:-appbundle}"
tool/codegen.sh
tool/fetch_benchmark_model.sh
flutter build "$artifact" --release --flavor "$flavor" \
  --target-platform android-arm64,android-x64 \
  --obfuscate --split-debug-info="build/symbols/$flavor"
