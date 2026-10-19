# Phone test APKs — 2026-10-08

Both APKs include the reply math formatting and installed-model metadata fixes.
No app source, dependency lockfile, release configuration or existing feature
was changed for this packaging request. `preservation-check.json` verifies the
implementation hashes and packaging inputs, including the restored benchmark.

| Artifact (relative to project root) | Bytes | Size | Bundled speed-test model |
| --- | ---: | ---: | --- |
| `build/emberwit-0.1.0-arm64-lite-20261008.apk` | 22,278,978 | 22.28 MB | No, matching the previous lite APK |
| `build/emberwit-0.1.0-arm64-20261008.apk` | 114,172,258 | 114.17 MB | Yes |

The lite package supports chat and model downloads; the bundled device speed
test requires the full package. The old undated APK files were preserved.
Both new packages have the same application ID (`app.emberwit`), version
(`0.1.0`, code `1`) and signing certificate as the previous lite APK. Android
should allow an in-place update without uninstalling or clearing app data.
This is certificate/package verification, not a physical-device install test.
These builds use the existing Android debug signing fallback for phone testing.

Flutter app code targets ARM64. The existing Gradle configuration additionally
packages some x86_64 native dependency libraries, as did the previous lite APK;
the APKs are not intended to run on x86_64 devices. Configuration was preserved.

## Verification

- Both `tool/security_audit.sh` runs passed. Raw logs, signature verification
  and Android package metadata are saved alongside this file.
- Both APKs contain all 20 bundled math fonts and their KaTeX MIT notice.
- ZIP inspection confirms the benchmark is present only in the full APK.
- `artifacts.json` records exact sizes, SHA-256 hashes, ABIs and signing checks.
- `preservation-check.json` confirms every previously delivered implementation
  file is unchanged, and the original 91,893,088-byte benchmark was restored.
- Earlier implementation verification remains 508 app tests, 22 FFI package
  tests and 3 app native-engine tests passing, with clean static analysis.
  Packaging introduced no source changes, so those tests were not repeated.

## Reproduction

Run from the project root with the existing Flutter SDK:

```bash
flutter build apk --release --flavor prod --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/symbols/prod-phone-20261008
cp build/app/outputs/flutter-apk/app-prod-release.apk \
  build/emberwit-0.1.0-arm64-20261008.apk
bash docs/development/2026-10-08-reply-formatting/evidence/phone-apks/build-lite.sh
```

The lite script temporarily holds the benchmark outside the assets directory
and restores it with an EXIT trap, including on a build error. It preserves
the existing `.gitkeep` and does not change `pubspec.yaml`.

Two initial full-build attempts using `--no-pub` failed because a generated
plugin registrant from debug/testing referenced `IntegrationTestPlugin`, which
is excluded from release builds. Running `flutter pub get` alone did not repair
that mode-specific generated file. Normal `flutter build` without `--no-pub`
regenerated the release registrant and succeeded. Flutter SDK code in
`flutter_command.dart` skips platform regeneration with `--no-pub`, while
`flutter_plugins.dart` filters dev dependencies in release mode. No manual
generated-file edit was needed. The failed logs and successful final log are
retained for review.

The build also emitted existing icon-font and DWARF debug-information warnings;
both artifacts nevertheless passed the project's release audit. No physical
phone was connected during verification.
