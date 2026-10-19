# Dependencies

Every dependency is pinned to an exact version in `pubspec.yaml`, and
`pubspec.lock` is committed. CI runs `flutter pub get --enforce-lockfile` and
audits the licenses of all runtime dependencies, direct and transitive, with
`very_good packages check licenses`. The allowed licenses are MIT, BSD-2-Clause,
BSD-3-Clause, Apache-2.0, Zlib, ISC and MPL-2.0.

MPL-2.0 is allowed because it is copyleft only per file: using an unmodified
MPL library puts no obligations on the rest of the app. Today it covers
`dbus` and `upower`, which battery_plus uses only on Linux desktop. They are
never compiled into the Android or iOS apps. If any MPL file is modified, the
modified file must be published. Dependabot opens weekly upgrade PRs.

Before you add a dependency, check that it is actively maintained, that its
license is on the allowlist, and that it does not duplicate an existing
dependency. Then add a row below in the same PR.

## Runtime

| Package | Version | License | Why |
|---|---|---|---|
| flutter_riverpod | 3.4.3 | MIT | State management and the only dependency injection mechanism. |
| riverpod_annotation | 4.0.7 | MIT | Annotations for Riverpod code generation. |
| go_router | 18.0.1 | BSD-3-Clause | Declarative routing, maintained by the Flutter team. Supports deep links and redirects, which the onboarding flow needs. |
| freezed_annotation | 3.1.0 | MIT | Annotations for immutable value types with `copyWith` and equality. |
| json_annotation | 4.12.0 | BSD-3-Clause | Annotations for JSON (de)serialization. The catalog manifest and exports use it. |
| intl | 0.20.3 | BSD-3-Clause | Formatting of numbers, dates and plurals, and the runtime for generated localizations. |
| flutter_localizations | SDK | BSD-3-Clause | Material and Cupertino strings for English and Bengali. |
| ffi | 2.2.0 | BSD-3-Clause | Native memory helpers (`calloc`, UTF-8 strings) for the llama.cpp bindings and the shared cancel flag. |
| device_info_plus | 13.2.0 | BSD-3-Clause | Device model, manufacturer, OS version, emulator detection and CPU ABIs on Android and iOS. Flutter Community Plus, widely used. |
| battery_plus | 7.1.1 | BSD-3-Clause | Battery level and charging state for the profile, and later the low battery warning. Pulls in `dbus` and `upower` (MPL-2.0, Linux only). |
| dio | 5.11.1 | MIT | HTTP client for the catalog: interceptors (HTTPS only, retry with backoff) and a certificate validation hook for SPKI pinning. |
| cryptography | 2.9.0 | Apache-2.0 | Ed25519 signature verification of the catalog (pure Dart, audited algorithm implementations). |
| crypto | 3.0.7 | BSD-3-Clause | SHA-256 of model files (streamed, in an isolate) and SPKI pins. Dart team package. |
| background_downloader | 9.6.2 | BSD-3-Clause | Resumable background downloads that survive app restarts; WorkManager/foreground service on Android, background URLSession on iOS; pause, resume, progress, speed, ETA, Wi-Fi only. |
| file_picker | 13.1.0 | MIT | System file picker for importing GGUF files. |
| shared_preferences | 2.5.5 | BSD-3-Clause | Small settings such as Wi-Fi only downloads. Flutter team package. |
| drift | 2.35.0 | MIT | Typed SQLite with reactive queries and migrations for the chat database. |
| sqlite3 | 3.6.0 | MIT | SQLite bindings; its build hook bundles SQLCipher (`hooks.user_defines.sqlite3.source: sqlcipher`). SQLCipher itself is BSD-3-Clause style (Zetetic), linking OpenSSL on Android (Apache-2.0). |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | Keeps the database key in the Android Keystore / iOS Keychain. |
| flutter_markdown_plus | 1.0.12 | BSD-3-Clause | Markdown rendering of replies (maintained fork of flutter_markdown). |
| markdown | 7.3.1 | BSD-3-Clause | Markdown parser; pinned because the app customises its syntaxes (HTML as text). |
| flutter_math_fork | 0.7.4 | Apache-2.0 (KaTeX fonts: MIT) | Typesets TeX equations in replies (`$...$`, `\(...\)`, `$$...$$`, `\[...\]`) offline with bundled fonts, no WebView. Brings flutter_svg, vector_graphics, provider, nested, tuple and path_parsing (MIT, BSD-3-Clause, BSD-2-Clause). |
| url_launcher | 6.3.2 | BSD-3-Clause | Opens links from replies after confirmation. Flutter team package. |
| uuid | 4.6.0 | MIT | Conversation and message ids. |
| local_auth | 3.0.2 | BSD-3-Clause | App lock: the system biometric / device credential prompt (BiometricPrompt on Android, LocalAuthentication on iOS). Flutter team package; the app never sees biometric data. |
| package_info_plus | 10.2.2 | BSD-3-Clause | App version and build number for the About section. Flutter Community Plus. |
| path_provider | 2.1.6 | BSD-3-Clause | Locates the app private support directory where models are stored. Flutter team package. |
| llama_ffi | path (`packages/llama_ffi`) | Own code + MIT (llama.cpp) | Our FFI plugin around llama.cpp. |

## Development

| Package | Version | License | Why |
|---|---|---|---|
| build_runner | 2.16.1 | BSD-3-Clause | Runs the code generators. |
| riverpod_generator | 4.0.9 | MIT | Generates Riverpod providers. |
| freezed | 4.0.2 | MIT | Generates immutable value types. |
| json_serializable | 6.14.1 | BSD-3-Clause | Generates JSON code. Unknown keys are ignored (`build.yaml`) so older app versions accept newer catalogs. |
| very_good_analysis | 11.0.0 | MIT | Strict lint rule set. |
| mocktail | 1.0.5 | MIT | Mocks without code generation. |
| drift_dev | 2.35.0 | MIT | Generates drift tables and queries. |
| shared_preferences_platform_interface | 2.4.2 | BSD-3-Clause | In-memory preferences store for tests. |
| ffigen (in llama_ffi) | 22.0.0 | BSD-3-Clause | Generates `llama_bindings.dart` from `llama.h`. Run by hand; the output is committed. |
| flutter_test, integration_test | SDK | BSD-3-Clause | Unit, widget, golden and on-device tests. |

## Tools used in CI (not app dependencies)

| Tool | Version | License | Why |
|---|---|---|---|
| very_good_cli | 1.5.0 | MIT | License audit of dependencies. |
| release-please action | 5.0.0 | Apache-2.0 | Semantic versioning and generated changelog. |

## Native code

| Component | Version | License | Why |
|---|---|---|---|
| llama.cpp (git submodule) | b11155 | MIT | GGUF model inference on CPU, with Metal on iOS. The most widely used on-device LLM runtime, actively maintained, and it supports every model family in the seed catalog. |
| llama.xcframework (iOS) | b11155 release | MIT | Official prebuilt iOS build with Metal, verified by sha256 in `Package.swift`. |
| LLVM OpenMP runtime (`libomp.so`, Android arm64) | NDK r28 | Apache-2.0 with LLVM exception | Thread pool used by ggml's CPU backend on arm64. |
| libc++ (`libc++_shared.so`, Android) | NDK r28 | Apache-2.0 with LLVM exception | C++ runtime shared by the llama.cpp libraries. |
| androidx.appcompat | 1.7.1 | Apache-2.0 | `Theme.AppCompat` parents for the launch themes, which the biometric prompt needs on Android 8. |

## Bundled model (downloaded at build time, not committed)

| File | License | Why |
|---|---|---|
| `assets/models/benchmark.gguf`: SmolLM2-135M-Instruct Q4_0, 91.9 MB | Apache-2.0 (Hugging Face) | Micro benchmark model: under the 100 MB budget, and loads and runs in a few seconds on low end phones. `tool/fetch_benchmark_model.sh` pins its sha256. Stored uncompressed in the APK (`noCompress "gguf"`) so it is copied out once with a known size. |

## Test fixtures (downloaded, not committed)

| File | License | Why |
|---|---|---|
| stories260K.gguf (1.2 MB) | MIT (karpathy/llama2.c) | Tiny model for native tests on CI. `packages/llama_ffi/tool/fetch_test_model.sh` pins its sha256. |

## Bundled assets

| Asset | License | Why |
|---|---|---|
| Noto Sans (Regular, Medium, Bold) | SIL OFL 1.1 | Latin text. Bundled because the app must render correctly without network access. |
| Noto Sans Mono (Regular) | SIL OFL 1.1 | Code blocks, identical on every device and offline. |
| Noto Sans Bengali (Regular, Medium, Bold) | SIL OFL 1.1 | Bengali text, including conjuncts, on devices without a good Bengali system font. |

The font license is registered with Flutter's `LicenseRegistry` at startup, so
it appears on the licenses screen.
