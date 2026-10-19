# Reply formatting and installed-model details

Requested on 2026-10-08 (Asia/Dhaka). The user authorized development after
reviewing the plan and asked for evidence for a later Claude review, while
preserving existing features.

## Scope and implementation

1. `ReplyMarkdown` now supports inline `$...$` / `\(...\)` and display
   `$$...$$` / `\[...\]` equations using pinned `flutter_math_fork 0.7.4`.
   Its fonts ship in the app; rendering needs neither network nor WebView.
   `reply_math.dart` supplies app-owned Markdown syntaxes and element builders.
   This preserves the existing HTML-as-text syntax, blocked images, link
   confirmation, selectable prose, code-copy buttons and whole-reply copying.
2. Parsing respects code spans/fences and escaped dollars. Dollar math requires
   non-space boundaries and must not close immediately before a digit, keeping
   ordinary prices such as `$10 and $20` as text. Explicit incomplete formulas
   remain visible as source until their closing delimiter arrives. Unsupported
   commands and malformed formulas fall back to their original source.
3. Parsed math trees are retained by the equation widget while its expression
   is unchanged. Expressions above 8192 characters bypass TeX parsing;
   macro expansion is bounded at 100. Math does not execute HTML or fetch images.
   Parser warnings are disabled so model content is not written to console logs.
4. Equations, code blocks and wide Markdown tables can scroll horizontally.
   Equation text uses the surrounding style/theme and has a semantics label
   containing the original formula. The existing reply-copy action still copies
   original Markdown/TeX, excluding hidden thinking content.
5. Installed-model cards now expose parameters, Bengali quality, localized
   description, license and device recommendation while retaining the existing
   verification/size line and delete confirmation. `_ModelDetails` shares those
   facts with available-model cards. No download/import/storage schema changed.
6. `ModelsState.entryForInstalled` prefers the saved `catalogEntry`, so details
   survive offline use, JSON restoration, catalog changes and catalog removal.
   Legacy verified records can fall back to current catalog metadata only when
   their SHA-256 matches. Imported models keep their unverified status and show
   a localized explanation for unknown metadata. No facts are inferred from
   filenames or attached to an unverified file.
7. Recommendations use `toSpec(isInstalled: true)`, preserving the existing
   engine's memory/speed rules while skipping the download-space check.
   Without a device profile, no speed is fabricated. Without a benchmark,
   the existing estimate explanation is shown. Actual per-reply measurements
   in the chat footer are untouched.

## Review artifacts

The repository had no commits and most files were untracked at the start.
An ordinary Git diff therefore cannot identify this change accurately.

- [Scoped unified diff](evidence/changes.patch) includes added source/tests and
  changes against saved preimages; PNG changes are in the manifest instead.
- [Changed paths and hashes](evidence/changed-files.json).
- [Original hashes](evidence/before-sha256.json) and `evidence/before/` contain
  exact preimages of the existing files examined for this implementation.
  The `.before` suffix prevents Dart tools from treating them as source.
- [Screenshots](evidence/screenshots/) contain four math-reply and four
  installed-model captures: English/Bengali, light/dark. These are widget-test
  renders on Linux, not claims of screenshots taken on physical phones.
- Raw build/test logs and a machine-readable full-suite report live in
  `evidence/`. Early failed runs are retained, with the corrections described
  below; use the final logs to assess the delivered result.

## Validation

- Full app suite: **508 passed, 0 failed**, including all 485 pre-existing tests
  and 23 added tests (`evidence/full-tests.log`, `evidence/full-tests.json`).
- Native inference adapter package: **22 passed**, including 12 native tests
  (`evidence/ffi-tests.log`).
- App native inference engine: **3 passed** (`evidence/engine-native-tests.log`).
- Flutter analysis: **no issues** (`evidence/analysis-final.log`).
- Formatting gate: **242 files, 0 changes** (`evidence/format-check.log`).
- Dependency delta: **9 additions, 0 existing upgrades/removals**
  (`evidence/dependency-delta.json`).
- UI detector: no findings; its Dart coverage is limited, so widget tests and
  direct capture inspection provide the main UI evidence (`ui-detector.json`).
- KaTeX font attribution is present in the generated notices
  (`evidence/font-license-check.txt`).
- Android development APK: **built successfully**, arm64-v8a and x86_64
  (`evidence/android-build.log`, `evidence/android-artifact.json`). Compilation
  took 128.3 seconds; the artifact includes 20 math font files and the MIT notice.
  The APK is at `build/app/outputs/flutter-apk/app-dev-debug.apk`.
  This is build evidence, not a claim of physical-phone or iOS testing.

Final structured results: [test summary](evidence/test-summary.json).

Focused verification: **38 tests passed** in `evidence/targeted-final.log`.
It covers all existing message-view tests plus delimiter parsing, the reported
tangent example, matrices/aligned equations, streaming, malformed and oversized
source, raw reply copying, wide math/tables/code at 320 logical pixels and 2x
text, installed details on download completion, offline JSON restoration,
catalog removal, Bengali large text, imported models, and installed-space rules.

Visual generation: **8 captures passed** in `evidence/golden-generation.log`.
Only the four existing `models_*.png` baselines were intentionally updated;
the four `math_reply_*.png` baselines are new. Other visual baselines were not
regenerated. All eight captures were inspected together before final validation.

The initial capability audit found database-dependent failures because the
host lacked `libsqlcipher.so`. This task built SQLCipher with the existing
`tool/build_host_sqlcipher.sh` into `/tmp/emberwit-sqlcipher`; it did not install
or replace a system library. See `evidence/sqlcipher-setup.log`.

First-pass corrections (retained for review): Dart analysis requested the
project's primary-constructor spelling and flagged one unused test import;
both were corrected. One new test expected `Unverified` instead of the existing
`Unverified import` label; the test was corrected and the product label retained.

## Reproduction

Use Flutter 3.47.3 / Dart 3.13.3 as pinned by the project. Resolve the lockfile
with `flutter pub get --enforce-lockfile` and run `tool/codegen.sh` if generated
files are absent. A host SQLCipher library is required for database tests:

```bash
tool/build_host_sqlcipher.sh /tmp/emberwit-sqlcipher
export LD_LIBRARY_PATH=/tmp/emberwit-sqlcipher/lib:$LD_LIBRARY_PATH
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub --exclude-tags native
export LLAMA_FFI_LIB_DIR="$PWD/packages/llama_ffi/build/host/bin"
flutter test --no-pub --tags native
cd packages/llama_ffi
flutter test --no-pub
```

To reproduce the Android artifact:

```bash
flutter build apk --no-pub --debug --flavor dev --target-platform android-arm64,android-x64
```

Do not use `--update-goldens` for validation: compare against the delivered
baselines. Tests for the new changes are in `reply_math_test.dart`,
`models_state_test.dart`, and the added cases in `models_page_test.dart`.

Generated localizations/package metadata were refreshed by Flutter and remain
ignored as in the existing project setup. No Git commit was created.

Phone-test release APKs were subsequently built on 2026-10-08: a 22.28 MB lite
package matching the earlier benchmark omission, and a 114.17 MB full package.
Both passed the release audit and match the old lite APK's application ID and
signing certificate. Build logs, artifact hashes, packaging preservation checks
and reproduction steps are in [phone APK evidence](evidence/phone-apks/README.md).

## Limits and review focus

- Math rendering changes presentation, not model inference or answer accuracy.
  It does not correct the erroneous claim that tan(90°) equals infinity.
- Support is for the renderer's TeX subset, not arbitrary LaTeX documents,
  executable HTML, embedded scripts, diagrams or external media. Unsupported
  TeX remains visible. Delimiter-less formulas are left as ordinary text.
- A formula inside an inline widget is not individually selectable as prose.
  Copying the whole reply preserves its exact TeX. Prose and code selection
  retain their existing behavior.
- An unmatched display opener keeps the remainder visible as source while
  streaming. We do not invent a closing delimiter or alter saved replies.
- Device speeds are estimates from the existing recommendation engine, not
  newly measured benchmarks for each installed model.
- Real-device testing and iOS builds require the respective device/macOS
  environment. Widget evidence must not be read as a completed device matrix.

Review parser boundaries, fallback behavior, narrow-layout constraints, copy
semantics and saved-versus-current catalog selection first. No inference,
database, encryption, downloader, app lock, onboarding, routing, native
platform code or release configuration was changed by this implementation.

## Dependency source and attribution

The [renderer documentation](https://pub.dev/packages/flutter_math_fork/versions/0.7.4)
and installed source were inspected. `flutter_math_fork` is Apache-2.0;
its bundled KaTeX fonts are MIT. `assets/fonts/KaTeX-LICENSE.txt` retains their
notice through Flutter's additional-licenses mechanism. The pinned lockfile
adds this renderer and its SVG/provider transitive dependencies; it does not
upgrade the project's existing dependencies. See the resolution log and
`docs/DEPENDENCIES.md` for rationale.
