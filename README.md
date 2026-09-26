<p align="center">
  <img src="docs/images/echoflow-icon.png" width="88" alt="EchoFlow app icon">
</p>

<h1 align="center">EchoFlow</h1>

<p align="center">Private, on-device dictation for macOS with Apple Speech, Parakeet v3, and Whisper.</p>

<p align="center"><a href="https://github.com/9phfr6dsw4-dotcom/echoflow/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+</p>

## Screenshots

<table>
  <tr>
    <td align="center"><strong>Speech models</strong><br><img src="docs/images/screenshots/speech-models.png" alt="EchoFlow speech model choices" width="100%"></td>
    <td align="center"><strong>Installed model details</strong><br><img src="docs/images/screenshots/model-library.png" alt="EchoFlow local model library" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>Local learning and vocabulary</strong><br><img src="docs/images/screenshots/settings-learning.png" alt="EchoFlow learning, vocabulary, and smart-link settings" width="100%"></td>
    <td align="center"><strong>Recording and cleanup controls</strong><br><img src="docs/images/screenshots/settings-controls.png" alt="EchoFlow recording behavior and text cleanup settings" width="100%"></td>
  </tr>
</table>

## Features

- Dictate with Apple Speech, Parakeet v3, or Whisper large-v3-turbo. Models are installed only when you choose them.
- Use a global hotkey and send finished text to the focused app.
- Review, edit, and copy transcript history stored on your Mac. Customize vocabulary and optional correction learning.
- Optionally pause Music or Spotify while dictating.

## Install

1. Download `EchoFlow.zip` from the [latest release](https://github.com/9phfr6dsw4-dotcom/echoflow/releases/latest) and unzip it.
2. Move **EchoFlow.app** to **Applications before opening it**.
3. Open it once. If macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**, confirm, then reopen EchoFlow from Applications.
4. Allow microphone access when you start dictation. To use the global hotkey and insert text into other apps, enable EchoFlow in **System Settings → Privacy & Security → Accessibility** when prompted. **Input Monitoring is not required.**
5. If you enable Music or Spotify controls, allow the optional Automation request.

The release is not notarized, so macOS may require approval on first launch.

## Privacy

Speech recognition runs on your Mac. Transcript history, preferences, vocabulary, and learning data stay local. Model and Apple Speech assets download only when you choose to prepare or install them; speech is not sent to a cloud transcription service. Saving audio is optional and off by default.

<details>
<summary>Build and test</summary>

The default branch contains the model manifest and integrity tests; the macOS app source is distributed in Releases.

```sh
swift test
```

</details>
