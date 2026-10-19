# llama_ffi

Dart FFI bindings for [llama.cpp](https://github.com/ggml-org/llama.cpp), used
by Emberwit's inference engine. This package is self contained and knows
nothing about the app. Isolates, streams and error mapping live in the app's
`lib/engine/`.

## What it provides

- `LlamaRuntime`: a small synchronous API (load, tokenize, decode, sample,
  chat template, devices). Every call blocks, so use it from a background
  isolate.
- `FfiLlamaRuntime`: the llama.cpp implementation.
- `LlamaLibrary`: opens the native library and registers compute backends.
- `readGgufHeader`: validates the GGUF magic and version without loading a
  model.

## How llama.cpp is built

| Platform | Build | Backends |
|---|---|---|
| Android arm64-v8a | CMake from `third_party/llama.cpp` (Gradle `externalNativeBuild`) | CPU, one module per ARM feature level: armv8.0, armv8.2 (dotprod), armv8.2+fp16, armv8.6 (i8mm), armv9.0, armv9.2. The best one for the phone is picked at runtime. |
| Android x86_64 (emulators) | CMake | Baseline CPU |
| iOS | Official prebuilt `llama.xcframework` from the release matching the submodule tag (Swift Package Manager; CocoaPods via `ios/fetch_xcframework.sh`) | CPU + Metal |
| Linux (desktop and tests) | CMake (`linux/CMakeLists.txt`, `tool/build_host.sh`) | CPU |

Windows and macOS need only a platform entry in `pubspec.yaml` plus the build
glue: `windows/CMakeLists.txt` like the Linux one, and macOS like iOS with the
same xcframework. The Dart code already knows their library names.

Vulkan (Android GPU) and KleidiAI are switched off for now. Vulkan is not yet
reliable across Android GPU drivers, and KleidiAI is downloaded at configure
time, which breaks offline, reproducible builds.

## Updating llama.cpp

1. `cd third_party/llama.cpp && git fetch --depth 1 origin tag bNNNN && git checkout bNNNN`
2. In `ios/llama_ffi/Package.swift` and `ios/fetch_xcframework.sh`, update the
   tag and the sha256 of `llama-bNNNN-xcframework.zip` (from the GitHub
   release page).
3. Regenerate the bindings: `dart run ffigen --config ffigen.yaml`. This needs
   libclang, for example from `pip install --user libclang`.
4. Rebuild and test on the host:
   ```bash
   tool/build_host.sh && tool/fetch_test_model.sh
   LLAMA_FFI_LIB_DIR=$PWD/build/host/bin flutter test
   ```
5. Build the app for Android and iOS (CI does both).

## Tests

```bash
flutter test --exclude-tags native                          # pure Dart tests
tool/build_host.sh && tool/fetch_test_model.sh
LLAMA_FFI_LIB_DIR=$PWD/build/host/bin flutter test         # plus the real llama.cpp
```

Native tests use `stories260K.gguf` (1.2 MB, MIT) and check loading, progress
and cancellation, tokenization round trips, deterministic greedy decoding, a
full context, chat templates and error codes.

## License

llama.cpp is MIT licensed. See `LICENSE`.
