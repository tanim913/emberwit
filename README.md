# Emberwit

<p>
  <a href="https://github.com/tanim913/emberwit/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/tanim913/emberwit?style=flat-square&label=download&color=FFB04A&labelColor=0B1020"></a>
  <img alt="Android 8.0 and newer" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?style=flat-square&labelColor=0B1020">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built_with-Flutter-54C5F8?style=flat-square&labelColor=0B1020">
  <img alt="No telemetry" src="https://img.shields.io/badge/telemetry-none-A5D6A7?style=flat-square&labelColor=0B1020">
  <img alt="MIT license" src="https://img.shields.io/badge/license-MIT-F2F4F8?style=flat-square&labelColor=0B1020">
</p>

**Emberwit** is a free, open-source AI assistant for Android that runs the AI
model on the phone itself. Download a model once, then chat in English or
Bengali with no internet, no account and no tracking. It keeps working in
airplane mode, during load-shedding, or when your data pack runs out.

<p align="center">
  <a href="https://github.com/tanim913/emberwit/releases/latest"><b>Download the latest APK</b></a>
  &nbsp;·&nbsp; <a href="https://tanim913.github.io/emberwit/">Website</a>
  &nbsp;·&nbsp; <a href="#install">How to install</a>
  &nbsp;·&nbsp; <a href="docs/PRIVACY_POLICY.md">Privacy policy</a>
</p>

## What it does

- **Runs offline.** The model lives in the app's private storage. The
  internet is used only to fetch the model list and download the models you
  pick.
- **Checks your phone first.** It measures memory, processor and speed, and
  only suggests models your phone can run well.
- **Eight models to choose from:** Qwen3 0.6B, 1.7B and 4B, Gemma 3 1B and
  4B, Llama 3.2 1B and 3B, and Phi-4 mini, from 0.5 to 2.5 GB. Every download
  is checked with SHA-256 against a signed list. You can also import your own
  GGUF file.
- **Answers in your language.** Each reply follows the language of your
  message: English, Bengali, or Bengali typed in English letters (Banglish).
  The whole app is in English and Bengali.
- **Voice typing** with your phone's offline speech recognizer, so your voice
  never leaves the phone.
- **Does things on your phone:** "set an alarm for 7 am", "timer for 10
  minutes", "turn on the flashlight", "open YouTube", in English or Bengali.
  A home-screen widget opens straight into voice.
- **Private by design:** chats are stored in an encrypted database, there is
  no account and no analytics, and an optional app lock uses your phone's PIN
  or fingerprint. Export and import your chats as an encrypted file.
- **Kind to your phone:** slows down or pauses when the phone is hot, the
  battery is low or memory runs short.
- Replies support Markdown, code blocks and math (LaTeX).

**Limits.** It cannot search the web or know today's news. Small models make
mistakes. The largest models need about 6 GB of memory; the smallest runs on
2 GB. Bengali voice typing works only if your phone offers Bengali offline.

## Install

1. On your phone, open the
   [latest release](https://github.com/tanim913/emberwit/releases/latest) and
   download the file ending in `arm64-v8a.apk`.
2. Open it. Android asks once to allow installs from your browser; allow it
   and tap **Install**.
3. Open Emberwit, let it check your phone, and download the model it suggests
   (Wi-Fi recommended).
4. Turn the internet off and keep chatting.

Needs Android 8.0 or newer, a 64-bit phone, and at least 2 GB of memory. Each
release lists the APK's SHA-256 checksum. Updates install over the old
version and keep your models and chats.

## For developers

Emberwit is built with Flutter and runs [llama.cpp](https://github.com/ggml-org/llama.cpp)
through its own FFI plugin (`packages/llama_ffi`) in a background isolate.

Docs: [ARCHITECTURE.md](ARCHITECTURE.md) · [SECURITY.md](SECURITY.md) ·
[CATALOG.md](CATALOG.md) · [docs/PERFORMANCE.md](docs/PERFORMANCE.md) ·
[docs/DEVICE_MATRIX.md](docs/DEVICE_MATRIX.md) ·
[docs/TEST_REPORT.md](docs/TEST_REPORT.md) ·
[docs/RELEASING.md](docs/RELEASING.md) ·
[docs/store/DATA_SAFETY.md](docs/store/DATA_SAFETY.md)

The project website is the single page in `docs/index.html` (with
`docs/site/`), served by GitHub Pages from the `docs` folder. It has no build
step; open it through any static server, for example
`python3 -m http.server -d docs`.

## Requirements

| Tool | Version |
|---|---|
| Flutter | 3.47.3 stable (Dart 3.13.3) |
| JDK | 17 |
| Android SDK | API 36, NDK 28.2.13676358 |
| Xcode (iOS only, macOS) | 16 or newer, iOS 15 deployment target |

Supported platforms are Android 8.0+ (API 26; arm64-v8a devices, x86_64
emulators) and iOS 15+.

## Setup

llama.cpp is a git submodule. Clone with submodules, or fetch them after
cloning:

```bash
git submodule update --init --recursive
tool/fetch_benchmark_model.sh   # 92 MB speed test model, bundled as an asset
flutter pub get --enforce-lockfile
tool/codegen.sh          # generates localizations, freezed, json and riverpod code
```

Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/gen/`) are not
committed. Run `tool/codegen.sh` after pulling or after changing an annotated
class or an ARB file. While developing, you can keep the generator running:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Running

Every build needs a flavor: `dev`, `staging` or `prod`.

```bash
flutter run --flavor dev
flutter run --flavor staging
flutter run --flavor prod --release
```

The first Android build compiles llama.cpp: 7 CPU variants for arm64 and one
for x86_64. That takes about 8 minutes on a 4 core machine. Later builds reuse
the native build.

A debug run without `--flavor` falls back to `dev`. A release build without a
valid flavor refuses to start and shows a configuration error screen.

| Flavor | App id | Name shown | Banner |
|---|---|---|---|
| dev | `app.emberwit.dev` | Emberwit Dev | DEV |
| staging | `app.emberwit.stg` | Emberwit Staging | STAGING |
| prod | `app.emberwit` | Emberwit | none |

All three can be installed side by side.

## Models

**Choose a model** on the home screen opens the models screen. It shows:

- models on the phone, with storage used, verification status and delete;
- downloads, with pause, resume, cancel, speed and time left;
- catalog models, each with a recommendation for this phone (Recommended,
  Runs slowly, Not supported) and the reason, size, parameters, Bengali
  quality and license.

**Download on Wi-Fi only** is on by default. **Import** (the file icon)
adds a GGUF file from device storage as an unverified model. How to add
models to the catalog and sign it is in [CATALOG.md](CATALOG.md).

## Device check

The home screen's **Check this device** button opens the device check. It
shows the performance class (tier), the suggested conversation memory, a
10 second speed test using the bundled model, and hardware details. Results
are cached in `device_profile.json` in app private storage. Without
`tool/fetch_benchmark_model.sh` the app still builds, and the speed test
reports that it is unavailable.

## Trying the engine (debug screen)

Dev and staging builds have an **Engine debug** button on the home screen. It
opens a screen that loads a GGUF model, streams a reply, and shows load time,
time to first token and tokens per second. Until the model manager exists,
copy a model into the app's private folder with:

```bash
curl -LO https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf
tool/push_debug_model.sh SmolLM2-135M-Instruct-Q4_K_M.gguf dev
```

On-device test and benchmark (the model must be pushed first):

```bash
flutter test integration_test/engine_smoke_test.dart --flavor dev
```

## Testing

```bash
flutter test                                   # unit, widget and golden tests
flutter test --coverage && dart run tool/coverage_check.dart   # coverage gate
flutter test --exclude-tags golden             # skip goldens (non-Linux hosts)
flutter test --tags golden --update-goldens    # regenerate goldens after a UI change
flutter test integration_test --flavor dev     # on a device or emulator
tool/security_audit.sh build/app/outputs/flutter-apk/app-prod-release.apk
```

Chat database tests need SQLCipher on the host. On Ubuntu 22.04 and newer,
`sudo apt install libsqlcipher-dev`. On older systems build it once and point
the loader at it:

```bash
tool/build_host_sqlcipher.sh ~/.local/sqlcipher
export LD_LIBRARY_PATH=~/.local/sqlcipher/lib:$LD_LIBRARY_PATH
```

Native tests run the real llama.cpp on the development machine (Linux or
macOS):

```bash
packages/llama_ffi/tool/build_host.sh          # needs CMake and a C++17 compiler
packages/llama_ffi/tool/fetch_test_model.sh    # 1.2 MB test model
export LLAMA_FFI_LIB_DIR=$PWD/packages/llama_ffi/build/host/bin
flutter test --tags native                     # engine end to end
(cd packages/llama_ffi && flutter test)        # package, including native
```

Golden images are generated on Linux, which is what CI uses. Font rendering
differs slightly on macOS and Windows, so exclude the `golden` tag there.

The coverage gate requires at least 80% line coverage on `lib/core`,
`lib/engine` and every feature's `domain` and `data` layers.

## Building

```bash
# Android
flutter build apk --debug --flavor dev --target-platform android-arm64,android-x64
tool/build_android.sh prod appbundle     # release: R8, obfuscated, symbols in build/symbols/prod
tool/build_release.sh                    # GitHub release APK + SHA-256 sums in dist/vX.Y.Z/

# iOS (macOS only)
flutter build ios --release --flavor prod --obfuscate --split-debug-info=build/symbols/prod
```

Always pass `--target-platform android-arm64,android-x64` (the script does
this). The Flutter CLI ignores Gradle `abiFilters`, so without it the APK also
contains 32-bit ARM code that the app does not support.

### Android release signing

Release builds are signed with the key described in
`~/.emberwit-release/key.properties` (set `EMBERWIT_SIGNING` to use another
path):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without that file, release builds fall back to the debug key so CI and fresh
clones still build. Never commit keystores or `key.properties`; `.gitignore`
blocks them.

Keep the `build/symbols/<flavor>` folder of every release you publish. You
need it to decode obfuscated stack traces with `flutter symbolize`.

## Renaming the app

To rename the app, edit:

1. `AppConstants.appName` in `lib/core/constants/app_constants.dart`
2. The `appName` manifest placeholders in `android/app/build.gradle.kts`
3. `FLAVOR_APP_NAME` in `ios/Runner.xcodeproj/project.pbxproj` (12 entries)

## Localization

Strings live in `lib/l10n/arb/`. `app_en.arb` is the template. Add every new
key to both `app_en.arb` (with a `@key` description) and `app_bn.arb`, then run
`flutter gen-l10n`. In widgets, use `context.l10n.someKey`. The parity test
fails if Bengali is missing a key or a placeholder.

## Project conventions

- Commits follow [Conventional Commits](https://www.conventionalcommits.org/).
  release-please derives the next semantic version and `CHANGELOG.md` from
  them.
- Dependencies are pinned exactly. See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).
- Never log user content: no prompts, model output, chat titles or file names.
- There are no hardcoded user facing strings.

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main`:

1. **quality**: codegen, format check, `flutter analyze --fatal-infos`, tests
   with coverage, the coverage gate, and a coverage summary on the run page.
1. **native**: builds llama.cpp for Linux and runs the llama_ffi and engine
   tests against the real library.
1. **licenses**: license audit of all runtime dependencies.
1. **android**: dev debug APK and prod release APK (R8, obfuscated), then
   `tool/security_audit.sh` on the release APK.
1. **ios**: dev debug and prod release builds without code signing, on macOS.

`.github/workflows/release-please.yml` maintains a release PR on `main`.
Merging it bumps `pubspec.yaml`, updates `CHANGELOG.md` and creates a tag.
Signed store builds run on tags in Codemagic (`codemagic.yaml`) or locally
with Fastlane (`fastlane/`). See [docs/RELEASING.md](docs/RELEASING.md).
