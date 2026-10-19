# Test report

Run on 2026-10-03, on the development machine (Linux x86_64, Flutter 3.47.3,
Dart 3.13.3) and an Android emulator (x86_64, API 36).

## Summary

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed` | Pass, 229 files |
| `flutter analyze --fatal-infos` (very_good_analysis 11) | No issues |
| Unit, widget, golden and architecture tests | **485 passed**, 0 failed |
| Native engine tests (`--tags native`, real llama.cpp) | 3 passed |
| `llama_ffi` package tests (including native) | 22 passed |
| Coverage, whole `lib/` | 91.0% (4502 of 4949 lines) |
| Coverage gate (`core`, `engine`, features' `domain` and `data`) | **89.2%** (minimum 80%) |
| License audit (very_good_cli) | 158 packages: BSD-3-Clause 124, MIT 24, Apache-2.0 7, MPL-2.0 3 (Linux only `dbus`/`upower`), BSD-2-Clause 1 |
| Release APK audit (`tool/security_audit.sh`) | Pass (warning: debug key, no release keystore on this machine) |
| Golden images | 24 (chat, device check, models, onboarding, settings, lock screen; en/bn × light/dark) |

## What the tests cover

| Area | Tests |
|---|---|
| Architecture | Import boundaries (features never import each other); security rules: no `print`, no `http://`, no user content in log calls, no keys in shipped files, manifest flags, permissions, network security config, iOS ATS |
| Engine | Isolate worker with a scripted runtime (load, generate, cancel, crash recovery), UTF-8 stream decoding of split Bengali characters, stop sequences, native end to end with a 260K test model, thread changes without reload |
| Device profiler | Snapshot parsing, tier classification, benchmark runner, profile cache, conditions source |
| Recommendations | Memory, storage and speed rules; five device matrix profiles |
| Catalog | Ed25519 envelope, unknown keys, tampering, rollback, malformed entries, SPKI pinning |
| Model manager | Downloads with mirror fallback, SHA-256 mismatch, atomic install, import validation, delete |
| Chat | SQLCipher encryption on disk, repository, restore, templates (ChatML, Gemma, Llama 3, Phi 4), control marker escaping, context planning, responder (including heat and battery refusal and thread throttling), markdown safety (HTML as text, blocked images, confirmed links) |
| Export/import | Round trip with Bengali text, wrong passphrase, tampered ciphertext and header, bounded KDF parameters, newer versions, duplicate import |
| Runtime safety | Policy thresholds, status expiry, supervisor polling, memory pressure, background unload |
| Settings | Theme, language, default model, export, import, delete chats and models, app lock toggle, model licenses |
| Onboarding | Suggestion without license agreement, download, skip, browse, redirect until done |
| App lock | Cold start lock, grace period, covering on `inactive`, failed and unavailable authentication, `FLAG_SECURE` only while locked |
| Localization | Every English key has a Bengali translation with the same placeholders; failure and runtime messages distinct in both languages |
| Accessibility | WCAG AA contrast for every text and control pair in both themes |

## On the emulator

| Check | Result |
|---|---|
| Fresh install starts on onboarding; four steps; suggestion shown | Pass |
| Settings: app lock refused without a screen lock, explained | Pass |
| App lock with a real PIN: enable, cold start locked, cancel shows retry, unlock | Pass |
| `FLAG_SECURE` on the window only while the lock screen shows | Pass (`dumpsys window`) |
| `am send-trim-memory RUNNING_CRITICAL` | App alive |
| Earlier phases: download and verify Qwen3 0.6B, chat streaming, encrypted `chat.db` | Pass (Phase 3 and 4 reports) |

## Not tested here

* Real phones (see `docs/DEVICE_MATRIX.md` for the plan and empty results
  table).
* iOS: builds only in GitHub Actions on macOS; never run on a device or
  simulator during development.
* Fastlane and Codemagic pipelines: written and syntax checked, not run
  (they need store credentials).
