#!/usr/bin/env bash
# Copies a GGUF model into the app's private models folder on a connected
# Android device or emulator, for the engine debug screen and on-device tests.
#
# Usage: tool/push_debug_model.sh <model.gguf> [dev|staging]
#
# Works only with debuggable builds (run-as). Production builds get models
# through the in-app downloader and importer instead.
set -euo pipefail
model="${1:?usage: tool/push_debug_model.sh <model.gguf> [dev|staging]}"
flavor="${2:-dev}"
case "$flavor" in
  dev) app_id="app.emberwit.dev" ;;
  staging) app_id="app.emberwit.stg" ;;
  *) echo "flavor must be dev or staging" >&2; exit 1 ;;
esac
name="$(basename "$model")"
adb push "$model" "/data/local/tmp/$name"
adb shell run-as "$app_id" sh -c "'mkdir -p files/models && cp /data/local/tmp/$name files/models/$name'"
adb shell rm "/data/local/tmp/$name"
echo "Pushed $name to $app_id files/models/"
