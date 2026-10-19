#!/usr/bin/env bash
# Regenerates all generated Dart code: localizations, freezed, json, riverpod.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
