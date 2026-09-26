# EchoFlow

_Formerly EchoType. Your settings, history, and downloaded models carry over; after installing EchoFlow.app, delete the old EchoType.app._

EchoFlow is a native SwiftUI/AppKit dictation app for **macOS 26 and later**. Speech recognition, transcript history, correction learning, vocabulary, and preferences stay on your Mac. The app does not use cloud transcription, accounts, analytics, crash reporting, or background update checks.

## Download

Download **EchoFlow.zip** and its **EchoFlow.zip.sha256** checksum from the [GitHub Releases page](https://github.com/9phfr6dsw4-dotcom/echotype/releases). Release builds are ad-hoc signed and not notarized. Ad-hoc signatures identify a specific build, so macOS may ask you to re-enable Accessibility after an update; a stable Developer ID signature is needed to preserve the same permission identity across releases. After extracting, move `EchoFlow.app` to Applications. On first launch, Control-click the app, choose **Open**, then confirm **Open** in macOS.

## One-time setup

1. Open EchoFlow and allow microphone access when macOS asks. EchoFlow requests microphone access only when you start Dictation, Voice Memo, or Voice Rewrite.
2. In Home → Dictation → Global hotkey, EchoFlow is on by default and restores its enabled/disabled choice across launches. If Accessibility access is missing, choose **Request Accessibility Access** to prompt macOS and open the Accessibility settings pane. Enable EchoFlow there, then return to the app. EchoFlow uses Accessibility only for global keyboard events and insertion; Input Monitoring is not required.
3. When Apple Speech is selected, EchoFlow checks Apple's installed language assets at launch and before each recording. If they are installed, it reuses them without prompting again. If missing, choose **Prepare Apple Speech** to install them; EchoFlow does not initiate that download silently. Parakeet and Whisper models download only after you explicitly choose them in Speech Models. One Parakeet download includes its vocabulary rescoring files, and **Delete Model** removes both. EchoFlow reuses already-installed files and downloads only missing files; adding a vocabulary term never downloads a model. Model downloads show their size and are checksum-verified.
4. Choose a microphone and adjust other options in Settings. The default hotkey is a bare Left Control tap; custom chords require an explicit modifier and do not consume the key event. If you enable Music/Spotify pausing, allow EchoFlow under Automation when macOS asks.

## Included

- Apple Speech, Parakeet v3, and Whisper large-v3-turbo local transcription, with explicit model installation and deletion and a pinned language preference.
- Global tap-to-toggle or hold-to-talk hotkeys, selectable modifier keys, custom key chords, and an optional backup chord.
- Voice Memo and Voice Rewrite have separate configurable chords (default ⌘⇧M and ⌘⇧R). Press a chord once to start; recording continues after you let go and finishes when you tap your Dictation hotkey or press the same chord again. Voice Memo writes a separate timestamp-named Markdown file in the chosen folder; Rewrite applies a spoken instruction to the selected text with Apple Intelligence on-device only. Rewrite is blocked in secure/excluded fields and leaves the selection unchanged if the model fails or the target selection changes. While EchoFlow runs, these chords are reserved for EchoFlow and are not passed to the frontmost app (so it does not beep or run its own command for them); change a chord in Settings if another app needs it.
- Recording overlay, Apple Speech live words, Dock icon cue, and optional start/stop sounds. Parakeet and Whisper display the final transcript after recording stops.
- Delivery to the text field focused when you stop dictation. EchoFlow inserts through Accessibility when available and otherwise sends targeted Unicode keyboard events to the same app; automatic dictation and Voice Rewrite never place their text on the clipboard. Changed apps, secure fields, and excluded password-manager apps remain blocked. Transcript **Copy** buttons are explicit and user-triggered. Optional Return submission is sent only when Accessibility confirms insertion; keyboard-event fallback never auto-submits.
- Microphone priority, app exclusions, local transcript history and retention, optional audio saving, Markdown archive (independent of local history), transcript editing, local correction learning, and custom vocabulary.
- Optional Music/Spotify pause and writable system-volume reduction during recording.

## Availability notes

- Learning from corrections in other apps is opt-in. When enabled, EchoFlow only observes selected text within a recent EchoFlow insertion in the same supported, non-secure, non-excluded field; the observation window is brief. Unsupported accessibility ranges or notifications are ignored. EchoFlow does not inspect window titles, URLs, or whole-field text.
- Browser media players are not controlled. Instant-on microphone is unavailable; the microphone is not left open between dictations.
- Parakeet's CTC vocabulary-rescoring files are part of its single model installation and are deleted with it. When upgrading an older installation, EchoFlow keeps verified files and downloads only missing pieces. Adding or editing custom terms never downloads a model. Apple Speech and Whisper use their supported local vocabulary-context mechanisms.
- Automated CI verifies tests, build, package, extracted app, and process launch. Real microphone, hotkey, insertion, media-control, overlay placement, and model latency still need testing on a physical Mac.

## Build and tests

```sh
swift test
bash Scripts/package-app.sh
bash Scripts/smoke-test.sh
```

The package targets macOS 26 and uses the pinned FluidAudio and WhisperKit Swift packages.
