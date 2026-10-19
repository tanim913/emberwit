#!/usr/bin/env bash
# Builds the llama.cpp shared libraries for the host machine (Linux or macOS)
# into build/host/bin. Used by the package's native tests and by the app's
# engine tests: export LLAMA_FFI_LIB_DIR=<package>/build/host/bin.
#
# Needs CMake >= 3.14 and a C++17 compiler. On the dev machine the Android
# SDK's CMake and Ninja work: PATH=$ANDROID_HOME/cmake/3.22.1/bin:$PATH
set -euo pipefail
cd "$(dirname "$0")/.."
jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
generator=()
if command -v ninja >/dev/null; then generator=(-G Ninja); fi
cmake -S src -B build/host "${generator[@]}" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/host --parallel "$jobs"
echo "Host libraries in $PWD/build/host/bin:"
ls build/host/bin
