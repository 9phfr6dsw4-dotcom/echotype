import AppKit
import EchoTypeCore
import SwiftUI

struct SpeechDictationPanel: View {
    @Environment(EchoTypeRuntime.self) private var runtime
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("EchoType.showLiveWords") private var showLiveWords = true
    @AppStorage("EchoType.copyToClipboard") private var copyToClipboard = false
    @AppStorage("EchoType.autoSend") private var autoSend = false

    private var dictation: SpeechDictationViewModel { runtime.dictation }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: dictation.isRecording ? "waveform.circle.fill" : "waveform")
                        .font(.title2)
                        .foregroundStyle(dictation.isRecording ? Color.red : Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(dictation.microphoneName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    actionButton
                }

                Text("Apple Speech needs its system assets prepared once. Parakeet and Whisper use only their downloaded local model files. Live words are available with Apple Speech; all backends delete temporary audio when transcription finishes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                hotkeySettings

                if dictation.isPreparingAssets || dictation.isTranscribing {
                    ProgressView(dictation.isPreparingAssets ? "Preparing Apple Speech…" : "Transcribing locally…")
                }

                if !dictation.transcript.isEmpty {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Transcript")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dictation.transcript, forType: .string)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(dictation.transcript)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let deliveryMessage = runtime.deliveryMessage {
                    Label(deliveryMessage, systemImage: "text.bubble")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = dictation.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } label: {
            Label("Dictation", systemImage: "mic")
        }
        .onAppear {
            runtime.overlayModel.showLiveWords = showLiveWords
            runtime.hotkey.refreshPermission()
        }
        .onChange(of: showLiveWords) { _, isVisible in
            runtime.overlayModel.showLiveWords = isVisible
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                runtime.hotkey.refreshPermission()
            }
        }
    }

    private var hotkeySettings: some View {
        GroupBox("Global hotkey") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    Picker("Tap to toggle", selection: Binding(
                        get: { runtime.hotkey.selectedKeyCode },
                        set: { runtime.hotkey.chooseKey(keyCode: $0) }
                    )) {
                        Text("Left Control").tag(UInt16(59))
                        Text("Right Option").tag(UInt16(61))
                    }
                    .frame(width: 245)

                    if runtime.hotkey.hasAccessibilityPermission {
                        Button(runtime.hotkey.isEnabled ? "Disable Hotkey" : "Enable Hotkey") {
                            if runtime.hotkey.isEnabled {
                                runtime.hotkey.disable()
                            } else {
                                runtime.hotkey.enable()
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Open Accessibility Settings") {
                            runtime.hotkey.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text(runtime.hotkey.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Show live words in the recording overlay", isOn: $showLiveWords)
                    .font(.caption)
                Toggle("Copy final text to clipboard and keep it there", isOn: $copyToClipboard)
                    .font(.caption)
                Toggle("Press Return after inserting text", isOn: $autoSend)
                    .font(.caption)
                if autoSend {
                    Text("Auto-send can submit a message or form in the target app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var actionButton: some View {
        Group {
            if dictation.isRecording {
                Button(role: .destructive) {
                    Task { await runtime.toggleRecording() }
                } label: {
                    Label("Stop and Transcribe", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
            } else if needsApplePreparation {
                Button {
                    Task { await dictation.prepareAppleSpeech() }
                } label: {
                    Label("Prepare Apple Speech", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(dictation.isPreparingAssets || dictation.isTranscribing)
            } else {
                Button {
                    Task { await runtime.startRecording() }
                } label: {
                    Label("Start Dictation", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(dictation.isPreparingAssets || dictation.isTranscribing || !canStartRecording)
            }
        }
    }

    private var selectedBackend: TranscriptionBackend? {
        guard let catalog = runtime.modelLibrary.catalog else { return nil }
        return TranscriptionBackend.resolve(
            engineID: runtime.modelLibrary.selectedEngineID,
            catalog: catalog,
            installedDownloadIDs: runtime.modelLibrary.installedDownloadIDs
        )
    }

    private var needsApplePreparation: Bool {
        selectedBackend == .appleSpeech && !dictation.assetsPrepared
    }

    private var canStartRecording: Bool {
        switch selectedBackend {
        case .some(.appleSpeech):
            dictation.assetsPrepared
        case .some(.parakeetV3), .some(.whisperLargeV3Turbo):
            runtime.modelLibrary.installedModelDirectory(for: runtime.modelLibrary.selectedEngineID) != nil
        case .some(.unavailable), .none:
            false
        }
    }

    private var statusTitle: String {
        if dictation.isRecording { return "Listening" }
        if dictation.isTranscribing { return "Finishing transcription" }
        if canStartRecording { return "Ready" }
        if needsApplePreparation { return "Apple Speech setup required" }
        return "Selected model unavailable"
    }
}
