# EchoType: product, model, and delivery research

**Reviewed:** September 24, 2026
**Target:** native macOS 26 dictation app for the user’s M5 MacBook Air.
**Privacy boundary:** speech, transcripts, corrections, preferences, and model use stay on the Mac. No telemetry or upload.

## Findings

VoiceInk documents local recognition and customization.[1] MacWhisper documents a global shortcut and overlay.[4]

VoiceInk’s issue tracker contains individual reports of recording-start delay and focus changing before paste.[2][3]

Separate MacWhisper user posts request additional shortcuts and glossary/context support.[28][29]

These are reports and feature requests, not measured failure rates.[2][3][28]

Secure keyboard input can block global shortcuts.[5] Listening for keyboard events requires macOS Input Monitoring.[10] EchoType will explain that permission separately from microphone access and Accessibility-based paste, use a listen-only event tap, and refuse to paste into a secure field or a target that changed after recording.

No controlled same-audio comparison among Apple Speech, Parakeet v3, and Whisper large-v3-turbo on an M5 MacBook Air was found in the sources reviewed.[13][22][23] EchoType will avoid promising a universal winner and record local processing times so the user can compare the same clip.

## Three-engine comparison

### Apple Speech

Apple provides SpeechAnalyzer and DictationTranscriber APIs for speech analysis and dictation.[6][8]

AssetInventory checks and installs speech assets for supported locales.[7]

Apple exposes contextual strings for vocabulary hints.[9]

### Parakeet v3

NVIDIA’s official 0.6B Parakeet-TDT-v3 source model is CC-BY-4.0.[11]
Its card lists Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Slovak, Slovenian, Spanish, Swedish, Russian, and Ukrainian.[11] FluidInference publishes a Core ML conversion, and FluidAudio provides the Swift runtime.[12][14]

FluidAudio v0.17.2 can load this selected bundle directly from a local folder.[53]

At pinned revision `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`, the selected int8-v2 bundle is **632,169,729 bytes** across 20 files.[15][46][50]

FluidInference also publishes a legacy `Encoder.mlmodelc` path; EchoType selects the version-2 encoder and does not include the legacy files.[16][46]

The encoder, decoder, joint-decision, and preprocessor weight entries have pinned file metadata.[47][48][49]

FluidAudio supports streaming transcription and vocabulary rescoring.[54]

The optional CTC companion is **2,373,826,395 bytes** across 9 files, and the upstream NVIDIA CTC model is CC-BY-4.0.[30][51][52]

Its conversion repository does not declare a license field, so the add-on will remain optional and EchoType will attribute both source and converter.[31][32][55]

### Whisper large-v3-turbo

OpenAI’s official large-v3-turbo model has 809M parameters and is MIT-licensed.[22][33]

Argmax publishes a matching Core ML conversion under MIT, and WhisperKit provides the local Swift runtime.[23][24][39]

At Argmax revision `0f63a7800b00dd0226abd051b906c246e1907482`, the converted bundle is **3,195,115,988 bytes** across 24 files.[25][26]

Six tokenizer assets from OpenAI revision `41f01f3fe87f28c78e2fbf8b568835947dd65ed9` add **4,560,441 bytes**, for **3,199,676,429 bytes total** (3.199676429 GB decimal / 2.979930890 GiB).[33][34][35]

WhisperKit v1.1.0 supports `promptTokens` for decoder context and live streaming from a selectable input device.[57][58]

It searches supplied local folders for `tokenizer.json` before falling back to the Hub; EchoType will bundle the pinned tokenizer and set `download: false`.[56][58]

The current FluidAudio main-branch loader and streaming/vocabulary implementation were cross-checked against the pinned release APIs.[40][41][42]

The same source comparison covered WhisperKit’s tokenizer lookup, streaming input, and local configuration.[43][44][45]

### Download and integrity policy

The Parakeet/CTC and OpenAI/Argmax model repositories are public and report no account gate.[15][25][32]

The OpenAI tokenizer repository is also ungated.[34]

Large Hugging Face LFS files expose publisher SHA-256 object IDs; EchoType will bundle hashes for the small regular Git files from their pinned commits as well.[26][35][46]

Downloads begin only after the user presses **Download**, the UI shows the exact byte total first, and any size/hash mismatch blocks installation.

The Parakeet TDT decoder itself is not described as having a custom lexicon; its vocabulary-rescoring path uses the separate CTC companion.[54][55]

Whisper uses decoder prompt tokens and Apple exposes contextual strings.[9][58]

The UI will distinguish these mechanisms from post-transcription spelling correction.

## Other models considered

- **Cohere Transcribe 2B:** the model card states Apache-2.0, but access requires sign-in and sharing contact information. Excluded.[20][21]
- **Qwen3-ASR 0.6B:** a public Apache-2.0 model and a community Swift port exist, but it is not one of the three requested engines and no publisher-backed Core ML package was verified for this app. Keep as a future review item, not a fourth picker entry.[17][18][19]
- **Qwen Audio 3.0:** a September 2026 paper appeared during research; an official local-weight package and license were not verified. Research-watch only.[27]

## Product and privacy decisions

| Area | Implementation choice |
|---|---|
| Engine selection | Exactly three choices. Apple is the working first-run fallback; after Parakeet has downloaded and loaded successfully, make it the default. Switching happens between recordings. |
| Live preview | Use the selected engine for partial and final text. Never label Apple preview as Parakeet or Whisper. Allow hiding live words while keeping a recording indicator. |
| Hotkeys | Left Control hold-to-talk and Right Option tap-to-toggle by default, with backup shortcut and configurable hold/tap behavior. Never consume shortcut events. |
| Overlay and focus | Non-activating overlay placed from the active display’s notch geometry (top-center fallback). Check foreground app and focused role before paste; respect secure fields/exclusions. On focus change, offer Copy instead. Save and restore clipboard around paste. |
| App presence | Keep a normal Dock icon and a reopenable settings/history window. |
| Storage | Audio stays in memory by default; optional audio saving is off initially. Local transcript history defaults to 30 days, with 7 days, 90 days, and forever choices. Retention never deletes learned terms. |
| Learning | Ask before adding learned terms by default and require repeated confirmation. External correction learning is opt-in, limited to the just-inserted text and a brief window, and skips secure/excluded targets. Never read screenshots, URLs, titles, or unrelated field content. |
| Vocabulary | Apple contextual strings, Whisper prompt tokens, and Parakeet CTC rescoring only when its optional companion is installed. |
| Comparison | Keep a recent clip in memory briefly for same-clip comparison; persist only if audio saving is enabled. Record local per-engine processing duration. |
| Network | No telemetry, analytics, update checks, or background model downloads. Only user-initiated model/Apple-asset downloads; never upload speech, transcript, corrections, filenames, or usage data. |

## Delivery and verification plan

Build a native SwiftUI/AppKit application targeting macOS 26.

Pin FluidAudio `v0.17.2` and WhisperKit `v1.1.0`.[38][39]

GitHub documents the standard `macos-26` runner and its architecture.[36][37]

Reports of runner-image assignment mismatch justify asserting `uname -m` is `arm64` before building.[59]

Run `swift test`, build and ad-hoc sign the app bundle, verify the extracted ZIP and executable, and perform a bounded launch smoke test. CI can verify compilation, tests, packaging, and process launch; real microphone permissions, paste behavior in target apps, audible quality, and M5 latency still require interactive testing on the user’s Mac.

## Sources

[1] https://github.com/Beingpax/VoiceInk — VoiceInk open-source dictation app
[2] https://github.com/Beingpax/VoiceInk/issues/572 — VoiceInk delayed recording-start report
[3] https://github.com/Beingpax/VoiceInk/issues/783 — VoiceInk focus-at-paste report
[4] https://docs.macwhisper.com/article/16-global — MacWhisper global hotkey and overlay
[5] https://docs.wisprflow.ai/articles/8841649969-Fix-Flow-shortcuts-blocked-by-macOS-Secure-Keyboard-Entry-/-Secure-Event-Input — Wispr Flow secure input limitations
[6] https://developer.apple.com/documentation/speech/speechanalyzer?changes=latest_major%2Clatest_major — Apple SpeechAnalyzer
[7] https://developer.apple.com/documentation/speech/assetinventory?changes=_1 — Apple AssetInventory
[8] https://developer.apple.com/documentation/speech/dictationtranscriber?changes=_1_9 — Apple DictationTranscriber
[9] https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings?changes=_1 — Apple contextual vocabulary
[10] https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29?language=objc — Apple Input Monitoring API
[11] https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 — NVIDIA Parakeet v3 official model card
[12] https://github.com/FluidInference/FluidAudio — FluidAudio Swift runtime
[13] https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md — FluidAudio publisher benchmark
[14] https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml — FluidInference Parakeet Core ML conversion
[15] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml — Parakeet conversion revision metadata
[16] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/Encoder.mlmodelc/weights?expand=true — Parakeet conversion weight SHA-256 metadata
[17] https://github.com/QwenLM/Qwen3-ASR — Qwen3-ASR official repository
[18] https://huggingface.co/Qwen/Qwen3-ASR-0.6B-hf — Qwen3-ASR official model card
[19] https://github.com/vfasky/qwen3-asr-swift — Community Qwen3-ASR Swift port
[20] https://huggingface.co/CohereLabs/cohere-transcribe-03-2026 — Cohere Transcribe model access and license
[21] https://huggingface.co/blog/CohereLabs/cohere-transcribe-03-2026-release — Cohere Transcribe release notes
[22] https://github.com/openai/whisper/blob/main/README.md?plain=1 — OpenAI Whisper official README
[23] https://github.com/argmaxinc/WhisperKit — WhisperKit Swift runtime
[24] https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3_turbo — Argmax Whisper Core ML model
[25] https://huggingface.co/api/models/argmaxinc/whisperkit-coreml — Whisper model revision metadata
[26] https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-large-v3_turbo?recursive=true&expand=true — Whisper per-file SHA-256 metadata
[27] https://arxiv.org/abs/2609.07549 — Qwen Audio 3.0 research report
[28] https://www.reddit.com/r/MacWhisper/comments/1qtua3l/feature_request_multiple_global_shortcuts_for — MacWhisper user request for additional hotkeys
[29] https://www.reddit.com/r/MacWhisper/comments/1tketgz/can_macwhisper_pro_take_contextglossary_before — MacWhisper user request for vocabulary context
[30] https://huggingface.co/nvidia/parakeet-ctc-0.6b — NVIDIA Parakeet CTC 0.6B original model and license
[31] https://huggingface.co/FluidInference/parakeet-ctc-0.6b-coreml — FluidInference Parakeet CTC Core ML conversion
[32] https://huggingface.co/api/models/FluidInference/parakeet-ctc-0.6b-coreml/tree/73c405fce92eb8264ea8f5b1260283eeee05aa27 — Parakeet CTC conversion pinned file hash metadata
[33] https://huggingface.co/openai/whisper-large-v3-turbo — OpenAI Whisper large-v3-turbo model and license
[34] https://huggingface.co/api/models/openai/whisper-large-v3-turbo — OpenAI Whisper tokenizer revision metadata
[35] https://huggingface.co/api/models/openai/whisper-large-v3-turbo/tree/41f01f3fe87f28c78e2fbf8b568835947dd65ed9 — OpenAI Whisper tokenizer per-file hashes
[36] https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners — GitHub macOS 26 hosted runner availability
[37] https://github.com/actions/runner-images — GitHub-hosted macOS runner image documentation
[38] https://github.com/FluidInference/FluidAudio/releases/tag/v0.17.2 — FluidAudio v0.17.2 release
[39] https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0 — WhisperKit v1.1.0 release
[40] https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift — FluidAudio local Parakeet loading API
[41] https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift — FluidAudio Parakeet streaming and vocabulary API
[42] https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/WordSpotting/CtcModels.swift — FluidAudio CTC contextual rescoring API
[43] https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Utilities/ModelUtilities.swift — WhisperKit local tokenizer lookup
[44] https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift — WhisperKit real-time audio streaming API
[45] https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Configurations.swift — WhisperKit local model-folder configuration
[46] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/Encoder_v2.mlmodelc/weights?expand=true — Parakeet v3 int8-v2 encoder SHA-256 metadata
[47] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/Decoder.mlmodelc/weights?expand=true — Parakeet decoder file sizes and SHA-256
[48] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/JointDecisionv3.mlmodelc/weights?expand=true — Parakeet joint-decision file sizes and SHA-256
[49] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/Preprocessor.mlmodelc/weights?expand=true — Parakeet preprocessor file sizes and SHA-256
[50] https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe?expand=true — Parakeet selected model bundle file inventory
[51] https://huggingface.co/api/models/FluidInference/parakeet-ctc-0.6b-coreml/tree/73c405fce92eb8264ea8f5b1260283eeee05aa27/AudioEncoder.mlmodelc/weights?expand=true — Parakeet CTC audio encoder SHA-256
[52] https://huggingface.co/api/models/FluidInference/parakeet-ctc-0.6b-coreml/tree/73c405fce92eb8264ea8f5b1260283eeee05aa27/MelSpectrogram.mlmodelc/weights?expand=true — Parakeet CTC mel spectrogram SHA-256
[53] https://github.com/FluidInference/FluidAudio/blob/v0.17.2/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift — FluidAudio v0.17.2 local Parakeet loader
[54] https://github.com/FluidInference/FluidAudio/blob/v0.17.2/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift — FluidAudio v0.17.2 streaming and vocabulary API
[55] https://github.com/FluidInference/FluidAudio/blob/v0.17.2/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/WordSpotting/CtcModels.swift — FluidAudio v0.17.2 CTC model loader
[56] https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Utilities/ModelUtilities.swift — WhisperKit v1.1.0 local tokenizer lookup
[57] https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift — WhisperKit v1.1.0 real-time streaming and input device
[58] https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Core/Configurations.swift — WhisperKit v1.1.0 prompt token configuration
[59] https://github.com/actions/runner-images/issues/14112 — macOS 26 runner architecture mismatch report
