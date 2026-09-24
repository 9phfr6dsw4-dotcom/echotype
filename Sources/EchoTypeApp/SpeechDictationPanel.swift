import AppKit
import SwiftUI

struct SpeechDictationPanel: View {
    @State private var dictation = SpeechDictationViewModel()

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

                Text("First use may download Apple’s system-managed speech assets after you choose Prepare. Live words are provisional; after you stop, a higher-quality local pass replaces them. Temporary audio is deleted when transcription finishes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
    }

    private var actionButton: some View {
        Group {
            if dictation.isRecording {
                Button(role: .destructive) {
                    Task { await dictation.stopAndTranscribe() }
                } label: {
                    Label("Stop and Transcribe", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
            } else if dictation.assetsPrepared {
                Button {
                    Task { await dictation.startRecording() }
                } label: {
                    Label("Start Dictation", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(dictation.isPreparingAssets || dictation.isTranscribing)
            } else {
                Button {
                    Task { await dictation.prepareAppleSpeech() }
                } label: {
                    Label("Prepare Apple Speech", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(dictation.isPreparingAssets || dictation.isTranscribing)
            }
        }
    }

    private var statusTitle: String {
        if dictation.isRecording { return "Listening" }
        if dictation.isTranscribing { return "Finishing transcription" }
        if dictation.assetsPrepared { return "Ready" }
        return "Apple Speech setup required"
    }
}
