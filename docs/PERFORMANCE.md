# Performance

How Emberwit stays fast on phones, and what was measured.

## Design choices

| Area | Choice | Why |
|---|---|---|
| Startup | `bootstrap` awaits only the support directory path and preferences; the database opens lazily in its own isolate; the engine isolate starts on first use | First frame is not blocked by I/O |
| Inference | llama.cpp in a long lived worker isolate; tokens cross isolates as text pieces | The UI isolate never runs model code |
| Threads | Performance cores only, at most 4; halved by heat or battery without reloading (`llama_set_n_threads`) | More threads than fast cores slow token generation on big.LITTLE |
| CPU features | Android loads the best `libggml-cpu` variant (armv8.0 to armv9.2) at runtime | dotprod and i8mm give 2 to 4x speedups on newer phones |
| Streaming UI | Tokens coalesced every 50 ms before markdown re-renders | Keeps frames inside 16 ms while text streams |
| Context | Planner counts real tokens and drops the oldest turns; reply reserve at most half the context | No failed generations from overflow |
| Model reuse | A loaded model is reused across chats when path and context fit | Avoids multi-second reloads |
| Memory | Model unloaded on OS memory warnings and after 3 minutes idle in the background | The OS kills apps holding gigabytes in the background |
| Hashing | SHA-256 of downloads streamed in an isolate | Verifying a 2 GB file does not freeze the UI |
| Lists | Conversations and messages are lazily built `ListView`s backed by indexed queries | Long histories scroll smoothly |
| APK | 64-bit ABIs only, R8, obfuscation, `--split-debug-info` | Smaller download, no 32-bit dead weight |

## Measurements (Android emulator, x86_64, 2 cores, software GPU)

| Metric | Value | Notes |
|---|---|---|
| Cold start, prod release | 2.8 s steady state (first launch after boot 9.4 s) | `am start -W`, includes software rendering |
| Idle memory, prod release | 74 MB PSS | Onboarding screen, no model loaded |
| Speed test (SmolLM2 135M Q4_0) | 18.7 tok/s, TTFT 247 ms, load 586 ms | Debug build; native code is optimised in every build type |
| Chat, Qwen3 0.6B Q4_K_M | 3.9 tok/s | No dotprod on x86_64; phones with dotprod are much faster |
| Release APK (universal) | 124 MB | arm64 libraries 37.7 MB, x86_64 33.9 MB, assets 95 MB |
| Per device download (arm64 from the app bundle, estimated) | about 110 MB | The 92 MB benchmark model is stored uncompressed and is most of it |

## Known costs and options

* The bundled benchmark model (92 MB) is the largest part of the download.
  It could move to an on-demand download or a Play Asset Delivery pack if
  install size matters more than an offline speed test.
* `llama.cpp` builds seven CPU variants for arm64 (about 6.5 MB). Dropping
  armv9 variants would save 2 MB at the cost of speed on new phones.
* Real phone numbers are pending; see `docs/DEVICE_MATRIX.md`.
