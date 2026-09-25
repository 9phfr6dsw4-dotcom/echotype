import EchoTypeCore
import Foundation
import Observation

@MainActor
@Observable
final class EchoTypeRuntime {
    let dictation: SpeechDictationViewModel
    let hotkey: GlobalHotkeyController
    let overlayModel: RecordingOverlayModel

    @ObservationIgnored private let overlayWindow: RecordingOverlayWindowController
    @ObservationIgnored private var dismissOverlayTask: Task<Void, Never>?

    init() {
        let dictation = SpeechDictationViewModel()
        let overlayModel = RecordingOverlayModel()
        self.dictation = dictation
        self.overlayModel = overlayModel
        self.hotkey = GlobalHotkeyController()
        self.overlayWindow = RecordingOverlayWindowController(model: overlayModel)

        dictation.onChange = { [weak self] state in
            self?.synchronizeOverlay(with: state)
        }
        hotkey.onToggleRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.toggleRecording()
            }
        }
    }

    func toggleRecording() async {
        if dictation.isRecording {
            overlayModel.phase = .finishing
            overlayWindow.show()
            await dictation.stopAndTranscribe()
            return
        }
        guard !dictation.isTranscribing else { return }
        guard dictation.assetsPrepared else {
            dictation.errorMessage = "Prepare Apple Speech in EchoType before using the global hotkey."
            return
        }
        await dictation.startRecording()
    }

    private func synchronizeOverlay(with dictation: SpeechDictationViewModel) {
        overlayModel.transcript = dictation.transcript

        if dictation.isRecording {
            dismissOverlayTask?.cancel()
            overlayModel.phase = .recording
            overlayWindow.show()
        } else if dictation.isTranscribing {
            dismissOverlayTask?.cancel()
            overlayModel.phase = .finishing
            overlayWindow.show()
        } else if !dictation.transcript.isEmpty {
            overlayModel.phase = .done
            overlayWindow.show()
            dismissOverlayTask?.cancel()
            dismissOverlayTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                self?.overlayWindow.hide()
            }
        } else {
            overlayModel.phase = .idle
            overlayWindow.hide()
        }
    }
}
