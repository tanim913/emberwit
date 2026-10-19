# Security

Emberwit keeps conversations on the phone. This document describes what the
app protects, from whom, how, and what it does not protect against. It is
written for reviewers and contributors.

## Reporting a vulnerability

Email the maintainer privately (address in the store listing) with steps to
reproduce. Do not open a public issue for a vulnerability. Expect an answer
within 7 days. Fixes ship in a patch release, and the reporter is credited
unless they ask not to be.

## Security promises

1. Chats never leave the device unless the user exports them, and an export
   is encrypted with a passphrase only the user knows.
2. The app has no accounts, analytics, crash reporting, ads or telemetry.
   Its only network traffic is the model catalog and model downloads.
3. Only models listed in a catalog signed by the Emberwit key are offered,
   and a downloaded file is installed only if its SHA-256 matches the
   catalog.
4. Model output is treated as untrusted input.

## Assets

| Asset | Where | Sensitivity |
|---|---|---|
| Conversations (messages, titles, system prompts) | `files/chat/chat.db`, SQLCipher (AES-256) | High |
| Database key (256 bit, random) | Android Keystore backed storage / iOS Keychain, this device only | High |
| Chat exports | Wherever the user saves them | High, protected by the passphrase |
| Model files | `files/models/` (private app storage) | Integrity matters; contents are public |
| Catalog signing private key | Offline, outside the repository (`~/.emberwit-release/`) | Critical: controls which models users get |
| Android upload key and passwords | Outside the repository (`key.properties`) | Critical |
| Preferences (theme, language, voice language, flags) | Shared preferences | Low, no personal data |
| Microphone audio during voice typing | Never stored; handed to the phone's on-device speech recognizer | High while listening |
| Device profile and benchmark | `files/device_profile.json` | Low |

## Actors and trust boundaries

```
 [User] -- touch --> [Emberwit UI isolate] -- ports --> [Engine isolate: llama.cpp]
                          |                                   ^
                          | SQLCipher                         | GGUF file (untrusted if imported)
                          v                                   |
                    [chat.db]  [Keystore/Keychain]       [files/models]
                          |
  HTTPS + SPKI pin + Ed25519 signature
                          v
 [tanim913.github.io]  [Hugging Face mirrors]   <- untrusted network
```

Adversaries considered:

* **A1, network attacker** (hostile Wi-Fi, ISP, compromised CDN or mirror).
* **A2, compromised catalog server or mirror**.
* **A3, other apps on the same phone** (no root).
* **A4, someone holding the unlocked phone briefly** (shoulder surfer,
  family member).
* **A5, someone with the locked phone** (theft, loss), or a backup of it.
* **A6, a malicious model file** the user imports.
* **A7, a model producing hostile output** (prompt injection, crafted links).

Out of scope: a rooted or jailbroken phone, a compromised OS, malware with
accessibility or screen capture rights, hardware attacks, and the user
deliberately sharing their exports and passphrase.

## Threats and mitigations (STRIDE)

| # | Threat | Actor | Mitigation | Where |
|---|---|---|---|---|
| T1 | Spoofed or altered catalog adds a malicious model | A1, A2 | Ed25519 signed envelope, verified before parsing; public keys compiled in; unknown key ids rejected | `signed_catalog.dart`, `catalog_trust.dart` |
| T2 | Catalog rollback to an old, vulnerable list | A1, A2 | `catalogVersion` must not decrease below the cached one | `catalog_repository_impl.dart` |
| T3 | Swapped or corrupted model download | A1, A2 | SHA-256 from the signed catalog checked in an isolate before the atomic rename into `models/`; mismatch deletes the file; mirrors are just transport | `model_library_impl.dart` |
| T4 | TLS interception of the catalog | A1 | HTTPS only (interceptor plus platform config); SPKI pinning hook for the catalog host; system trust store only, user CAs ignored on Android | `secure_http_client.dart`, `network_security_config.xml` |
| T5 | Reading chats from storage | A3, A5 | SQLCipher AES-256 database; raw 256-bit key in Keystore/Keychain (`first_unlock_this_device`); private app storage; an unreadable database is moved aside, never sent anywhere | `chat_database.dart` |
| T6 | Chats leaking through backups or device transfer | A5 | `allowBackup="false"`, data extraction rules exclude everything, iCloud backup exclusion on the chat and model directories | `AndroidManifest.xml`, `backup_exclusion.dart` |
| T7 | Casual access to an unlocked phone | A4 | Optional app lock (biometrics or device credential, OS lockout on repeated failure); locks on cold start and after 30 s away; changing it requires authentication | `features/app_lock` |
| T8 | Chats visible in the app switcher or screenshots of the lock state | A4 | The app covers itself as soon as it becomes inactive; `FLAG_SECURE` while the lock screen shows | `app_lock_gate.dart`, `MainActivity.kt` |
| T9 | Keyboard learning private text | A3 | `enableIMEPersonalizedLearning: false` on chat, rename, system prompt and passphrase fields | chat and settings pages |
| T10 | Exports read by whoever holds the file | A3, A5 | Argon2id (19 MiB, 2 passes, random salt) and AES-256-GCM; header authenticated; minimum 8 character passphrase | `chat_archive_codec.dart` |
| T11 | Crafted export exhausting memory or CPU | A6-like file | KDF parameters bounded (≤ 64 MiB, ≤ 10 passes) before deriving; import size capped at 256 MB; parse errors become a typed failure | `chat_archive_codec.dart`, `archive_files.dart` |
| T12 | Malicious GGUF exploiting the parser | A6 | Header and version validated before copying; imported models labelled Unverified; parsing happens in a separate isolate (same process, so this limits blast radius only for Dart state); llama.cpp pinned and updated by tag | `gguf.dart`, `llama_worker.dart` |
| T13 | Model output running code or fetching content | A7 | Markdown without HTML (HTML shown as text); images never fetched; links open only after showing the full address and only for http, https and mailto; chat template control markers in user text are neutralised | `message_view.dart`, `chat_template.dart` |
| T14 | Information disclosure in logs | A3 | Release builds use a silent logger; log messages never include chat text, prompts, titles, file names or passphrases (enforced by a test); Android `Log.v/d/i` stripped by R8 | `app_logger.dart`, `security_rules_test.dart`, `proguard-rules.pro` |
| T15 | Reverse engineering secrets out of the app | anyone | No secrets in the app: only public keys and pins; Dart obfuscated; release audit checks for keys inside the APK | `tool/security_audit.sh` |
| T16 | Denial of service by heat, battery or memory | device | Runtime supervisor stops or slows generation and unloads the model on memory pressure | `runtime_supervisor.dart` |
| T17 | Supply chain: malicious dependency update | upstream | Exact version pins and committed lockfile (`--enforce-lockfile` in CI); license audit; Dependabot proposals are reviewed; GitHub Actions pinned by commit SHA; llama.cpp submodule and xcframework pinned (sha256) | `pubspec.yaml`, `.github/` |
| T18 | Exported Android components abused by other apps | A3 | Only the launcher activity is exported by the app; plugin services are protected by system permissions; checked by a test and the release audit | `security_rules_test.dart`, `tool/security_audit.sh` |
| T19 | Voice typing sending speech off the phone | A1, A3 | Only `createOnDeviceSpeechRecognizer` on Android 12+, no fallback to the network recognizer; `EXTRA_PREFER_OFFLINE` on Android 8 to 11; audio never stored; recognized text goes only into the message field; `RECORD_AUDIO` asked on first use | `VoiceInputChannel.kt`, `voice_typing.dart` |
| T20 | Chat text running phone actions | A7, A3 | Only the user's own message is parsed, never model output; fixed rules, short imperative messages only; actions limited to alarm, timer, flashlight and opening a launcher app the user named; the clock app shows the alarm it set; no app list stored | `device_command.dart`, `DeviceActionsChannel.kt` |
| T21 | Other apps triggering the voice widget or launch action | A3 | The widget receiver requires `BIND_APPWIDGET` (system only); the launch action only opens a new chat and starts listening after the app lock, with the system mic indicator | `VoiceWidgetProvider.kt`, `launch_actions.dart` |

## Residual risks

* **Unlocked, rooted or compromised devices** can read everything the app
  can. SQLCipher protects data at rest only while the key is unavailable.
* **App switcher snapshot timing.** The cover is drawn on `inactive`, which
  normally happens before the OS takes its snapshot. Some Android launchers
  may still capture a frame earlier. `FLAG_SECURE` is deliberately not set
  on normal screens (it would also block the user's own screenshots).
* **The clipboard.** Copying a reply puts it on the system clipboard, where
  other apps and clipboard history can read it. This is the user's choice.
* **Imported models.** llama.cpp parses the whole GGUF file. A parser bug
  could crash or compromise the app process. Only import files from sources
  you trust.
* **Debug builds** log diagnostics (never chat content) to the developer
  console.
* **The catalog is served from GitHub Pages without SPKI pins.** GitHub
  rotates its certificates, so pins would break the fetch. Integrity rests on
  the Ed25519 signature; when the fetch fails, the app uses the bundled
  catalog, which is equally signed.
* **The current catalog key is a development key.** A production key must
  be generated offline before the first store release (see below).

## Release checklist

1. Generate the production catalog key on an offline machine
   (`dart run tool/catalog/keygen.dart`), add its public key to
   `catalog_trust.dart`, remove the development key, and re-sign the bundled
   catalog. Store the private key offline, with a second copy in a safe.
2. Deploy the catalog host, then add its SPKI pins (current and backup key)
   to `certificate_pins.dart`.
3. Build with `tool/build_android.sh prod appbundle` and run
   `STRICT=1 tool/security_audit.sh` on the universal APK from the bundle.
4. Keep `build/symbols/` for the release to decode stack traces.
5. Run the device matrix in `docs/DEVICE_MATRIX.md`.

## Verified on

Phase 6 (2026-10-03), Android emulator API 36 with the prod release APK:
`tool/security_audit.sh` passes (debug key warning only); the app lock with a
real device PIN set `FLAG_SECURE` only while locked; the chat database file
starts with random bytes (no `SQLite format 3` header).
