# Device matrix

The recommendation engine is tested against the five target devices from the
requirements. Until real devices are measured, the devices are
simulated in `test/core/recommendation/device_matrix_test.dart` using reported
RAM and an assumed speed test result for the bundled 92 MB model.

| Device | Reported RAM | Assumed speed test | Tier |
|---|---|---|---|
| Low end Android (4 GB) | 3.7 GiB | 30 tok/s | low |
| Mid range Android (6 GB) | 5.6 GiB | 70 tok/s | mid |
| Flagship Android (12 GB) | 11.2 GiB | 300 tok/s | flagship |
| Older iPhone (iPhone 11, 4 GB) | 3.8 GiB | 90 tok/s | low |
| Recent iPhone (15 Pro, 8 GB) | 7.5 GiB | 350 tok/s | high |

Resulting recommendations for the seed catalog (Q4_K_M):

| Model | Low Android | Mid Android | Flagship Android | iPhone 11 | iPhone 15 Pro |
|---|---|---|---|---|---|
| Qwen3 0.6B | Runs slowly (4.6) | Recommended (10.8) | Recommended | Recommended (13.9) | Recommended |
| Gemma 3 1B | Runs slowly (2.8) | Runs slowly (6.5) | Recommended | Recommended (8.3) | Recommended |
| Llama 3.2 1B | Runs slowly (2.8) | Runs slowly (6.5) | Recommended | Recommended (8.3) | Recommended |
| Qwen3 1.7B | Not supported (speed) | Runs slowly (4.1) | Recommended | Runs slowly (5.2) | Recommended |
| Llama 3.2 3B | Not supported | Runs slowly (2.6) | Recommended (11.1) | Not supported | Recommended (12.9) |
| Gemma 3 4B, Phi 4 mini, Qwen3 4B | Not supported (memory) | Not supported (memory) | Recommended (about 9) | Not supported (memory) | Recommended (about 10.5) |

Numbers in brackets are estimated tokens per second.

## Measured so far

| Device | Build | Result |
|---|---|---|
| Android emulator, x86_64, 2 cores, API 36 | debug | Speed test 18.7 tok/s, TTFT 247 ms, load 586 ms (bundled SmolLM2 135M) |
| same | debug | Qwen3 0.6B Q4_K_M chat: 3.9 tok/s; download 484,220,320 bytes verified and installed |
| same | prod release | Cold start to first frame 2.8 s (steady state, software GPU); idle memory 74 MB PSS |
| same | dev debug | Onboarding, settings, app lock with a device PIN, `FLAG_SECURE` only while locked, memory trim without crash |

The emulator has no performance cores, no dotprod and a software renderer,
so these numbers are a floor, not a prediction for phones.

## Test plan for real devices

Run on each device, release build (`tool/build_android.sh prod apk` or the
iOS archive from CI). Record each row as pass/fail with notes.

| # | Check | How | Pass when |
|---|---|---|---|
| 1 | Cold start | `adb shell am start -W` (Android), Xcode Instruments App Launch (iOS), 5 runs | Median under 1.5 s on mid range and up |
| 2 | Speed test | Settings > Device check > Run speed test | Finishes in under 15 s; tier matches the table above |
| 3 | Recommendations | Models screen | Labels match the estimates above within one step |
| 4 | Download | Download the top recommended model on Wi-Fi; lock the phone for 2 minutes | Completes, verified, survives screen off |
| 5 | Chat speed | Ask the same English and Bengali question (below) | Tok/s within 30% of the estimate; Bengali renders correctly |
| 6 | Stop and context | Stop a reply; continue a 30 message chat | Partial reply kept; "older messages left out" shown, no crash |
| 7 | Heat | Generate continuously for 10 minutes | Banner appears when hot; generation stops on critical; no OS kill |
| 8 | Battery | Battery saver on; then below 15% unplugged | Banner shown; replies slower; under 5% replies refused |
| 9 | Memory | Open the camera and two heavy apps while a model is loaded, return | App alive or restored; model reloads on the next message |
| 10 | App lock | Turn on, background 40 s, return; cancel the prompt | Lock shown; content hidden in app switcher; screenshot blocked on lock |
| 11 | Export/import | Export with a passphrase, clear chats, import | All chats back; wrong passphrase rejected |
| 12 | Airplane mode | Airplane mode, chat | Works fully offline |
| 13 | Bengali UI | Set app language to বাংলা | No clipped or missing text on every screen |
| 14 | Font scale | System font size largest | Every screen usable, no overflow |
| 15 | TalkBack / VoiceOver | Navigate onboarding and chat | Every control announced |

Questions for row 5: "Explain photosynthesis in three sentences." and
"সালোকসংশ্লেষণ তিন বাক্যে ব্যাখ্যা করুন।"

## Results on real devices

Not measured yet: no physical devices were available while building. Fill
this table, then tune `RecommendationConfig.bandwidthEfficiency` and the
tier thresholds in `DeviceTierClassifier`.

| Device | Speed test | Model | Tok/s (est. / real) | Cold start | Checks 1 to 15 |
|---|---|---|---|---|---|
| Low end Android (4 GB) | | | | | |
| Mid range Android (6 GB) | | | | | |
| Flagship Android (12 GB) | | | | | |
| iPhone 11 | | | | | |
| iPhone 15 Pro | | | | | |
