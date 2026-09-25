import AppKit
import EchoTypeCore
import Foundation
import Observation

@MainActor
@Observable
final class EchoTypeRuntime {
    let dictation: SpeechDictationViewModel
    let hotkey: GlobalHotkeyController
    let overlayModel: RecordingOverlayModel
    let textInsertion: TextInsertionService

    var deliveryMessage: String?

    @ObservationIgnored private let overlayWindow: RecordingOverlayWindowController
    @ObservationIgnored private var dismissOverlayTask: Task<Void, Never>?
    @ObservationIgnored private var capturedInsertionTarget: CapturedInsertionTarget?
    @ObservationIgnored private var workspaceActivationObserver: NSObjectProtocol?
    @ObservationIgnored private var isDeliveringTranscript = false

    init() {
        let dictation = SpeechDictationViewModel()
        let overlayModel = RecordingOverlayModel()
        self.dictation = dictation
        self.overlayModel = overlayModel
        self.hotkey = GlobalHotkeyController()
        self.textInsertion = TextInsertionService()
        self.overlayWindow = RecordingOverlayWindowController(model: overlayModel)

        dictation.onChange = { [weak self] state in
            self?.synchronizeOverlay(with: state)
        }
        hotkey.onToggleRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.toggleRecording()
            }
        }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.dictation.isRecording,
                      self.textInsertion.isFrontmostAppExcluded() else { return }
                await self.discardRecordingInExcludedApp()
            }
        }
    }

    func startRecording() async {
        guard !textInsertion.isFrontmostAppExcluded() else {
            dictation.errorMessage = "Dictation is disabled while a password manager is frontmost."
            return
        }
        dismissOverlayTask?.cancel()
        deliveryMessage = nil
        capturedInsertionTarget = textInsertion.captureTarget()
        await dictation.startRecording()
        if !dictation.isRecording {
            capturedInsertionTarget = nil
        }
    }

    func toggleRecording() async {
        if dictation.isRecording {
            if textInsertion.isFrontmostAppExcluded() {
                await discardRecordingInExcludedApp()
                return
            }
            isDeliveringTranscript = true
            overlayModel.phase = .finishing
            overlayWindow.show()
            await dictation.stopAndTranscribe()
            let outcome = await textInsertion.deliver(
                dictation.transcript,
                capturedTarget: capturedInsertionTarget,
                copyToClipboard: UserDefaults.standard.bool(forKey: "EchoType.copyToClipboard"),
                autoSend: UserDefaults.standard.bool(forKey: "EchoType.autoSend")
            )
            deliveryMessage = Self.message(for: outcome)
            capturedInsertionTarget = nil
            isDeliveringTranscript = false
            synchronizeOverlay(with: dictation)
            return
        }
        guard !dictation.isTranscribing else { return }
        guard dictation.assetsPrepared else {
            dictation.errorMessage = "Prepare Apple Speech in EchoType before using the global hotkey."
            return
        }
        await startRecording()
    }

    private func discardRecordingInExcludedApp() async {
        await dictation.cancelAndDiscardRecording()
        capturedInsertionTarget = nil
        deliveryMessage = "Recording discarded because a password manager became active."
        overlayModel.phase = .idle
        overlayWindow.hide()
    }

    private func synchronizeOverlay(with dictation: SpeechDictationViewModel) {
        overlayModel.transcript = dictation.transcript

        if dictation.isRecording {
            dismissOverlayTask?.cancel()
            overlayModel.phase = .recording
            overlayWindow.show()
        } else if dictation.isTranscribing || isDeliveringTranscript {
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

    private static func message(for outcome: TextInsertionService.Outcome) -> String {
        switch outcome {
        case .inserted:
            "Inserted into the same text field where dictation started."
        case .insertedAndSubmitted:
            "Inserted and sent with Return."
        case .copyOnly(.targetUnavailable):
            "Not pasted: EchoType could not verify the original text field. Use Copy in the transcript."
        case .copyOnly(.targetChanged):
            "Not pasted: the app or focused text field changed during dictation. Use Copy in the transcript."
        case .copyOnly(.excludedApplication):
            "Not pasted in an excluded password manager."
        case .copyOnly(.secureField):
            "Not pasted into a secure field. Use Copy only if you intend to place the text there."
        case .copyOnly(.notTextInput):
            "Not pasted because the original focus was not a recognized text field. Use Copy in the transcript."
        case .failed:
            "Text could not be inserted. The transcript remains available in EchoType."
        }
    }
}
