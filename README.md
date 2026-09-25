# EchoType

EchoType is a native SwiftUI/AppKit dictation app for **macOS 26 and later**. Speech recognition, transcript history, correction learning, vocabulary, and preferences stay on your Mac. The app does not use cloud transcription, accounts, analytics, crash reporting, or background update checks.

## Download

Download **EchoType.zip** and its **EchoType.zip.sha256** checksum from the [GitHub Releases page](https://github.com/9phfr6dsw4-dotcom/echotype/releases). Release builds are ad-hoc signed and not notarized. After extracting, move `EchoType.app` to Applications. On first launch, Control-click the app, choose **Open**, then confirm **Open** in macOS.

## One-time setup

1. Open EchoType and allow microphone access when macOS asks. EchoType requests microphone access only when you start dictation.
2. In Home → Dictation → Global hotkey, choose **Open Accessibility Settings**, turn on EchoType, then return to the app and enable the hotkey. Accessibility is used for global hotkeys, secure-field checks, and text insertion.
3. In **Speech Models**, prepare Apple Speech or explicitly download a local model. Model downloads show their size and are checksum-verified. The Parakeet button shows the combined size of Parakeet and its custom-vocabulary companion before starting. Apple Speech may download Apple-provided on-device language assets when you choose **Prepare Apple Speech**.
4. Choose a microphone and adjust other options in Settings. The default hotkey is a bare Left Control tap; custom chords require an explicit modifier and do not consume the key event. If you enable Music/Spotify pausing, allow EchoType under Automation when macOS asks.

## Included

- Apple Speech, Parakeet v3, and Whisper large-v3-turbo local transcription, with explicit model installation and deletion and a pinned language preference.
- Global tap-to-toggle or hold-to-talk hotkeys, selectable modifier keys, custom key chords, and an optional backup chord.
- Recording overlay, Apple Speech live words, Dock icon cue, and optional start/stop sounds. Parakeet and Whisper display the final transcript after recording stops.
- Safe insertion into the original supported text field, clipboard restoration by default, optional keep-on-clipboard and Return submission.
- Microphone priority, app exclusions, local transcript history and retention, optional audio saving, Markdown archive (independent of local history), transcript editing, local correction learning, and custom vocabulary.
- Optional Music/Spotify pause and writable system-volume reduction during recording.

## Availability notes

- Learning from corrections in other apps is opt-in. When enabled, EchoType only observes selected text within a recent EchoType insertion in the same supported, non-secure, non-excluded field; the observation window is brief. Unsupported accessibility ranges or notifications are ignored. EchoType does not inspect window titles, URLs, or whole-field text.
- Browser media players are not controlled. Instant-on microphone is unavailable; the microphone is not left open between dictations.
- Parakeet's custom-vocabulary CTC companion is a separate 2.37 GB model. It downloads automatically with Parakeet after the combined total is shown; if you already have Parakeet, adding or editing a custom term starts the companion download. Settings shows its install, download, or error status. If it is missing or fails, Parakeet's base transcript still works; Apple Speech and Whisper use their supported local vocabulary-context mechanisms.
- Automated CI verifies tests, build, package, extracted app, and process launch. Real microphone, hotkey, insertion, media-control, overlay placement, and model latency still need testing on a physical Mac.

## Build and tests

```sh
swift test
bash Scripts/package-app.sh
bash Scripts/smoke-test.sh
```

The package targets macOS 26 and uses the pinned FluidAudio and WhisperKit Swift packages.
