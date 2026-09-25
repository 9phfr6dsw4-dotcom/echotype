import AppKit
import EchoTypeCore
import Foundation
import Observation

@MainActor
@Observable
final class EchoTypeRuntime {
    let dictation: SpeechDictationViewModel
    let modelLibrary: ModelLibraryViewModel
    let history: TranscriptHistoryViewModel
    let localLearning: LocalLearningViewModel
    let customVocabulary: CustomVocabularyViewModel
    let excludedApplications: ExcludedApplicationsViewModel
    let microphones: MicrophoneSettingsViewModel
    let hotkey: GlobalHotkeyController
    let overlayModel: RecordingOverlayModel
    let textInsertion: TextInsertionService
    let recordingFeedback: RecordingFeedbackController
    let recordingAudioOptions: RecordingAudioOptionsController

    var deliveryMessage: String?

    @ObservationIgnored private let overlayWindow: RecordingOverlayWindowController
    @ObservationIgnored private var dismissOverlayTask: Task<Void, Never>?
    @ObservationIgnored private var capturedInsertionTarget: CapturedInsertionTarget?
    @ObservationIgnored private var workspaceActivationObserver: NSObjectProtocol?
    @ObservationIgnored private var isDeliveringTranscript = false
    @ObservationIgnored private var recordingStartedAt: Date?
    @ObservationIgnored private var recordingEngineID: String?

    init() {
        let microphones = MicrophoneSettingsViewModel()
        let dictation = SpeechDictationViewModel(microphoneSettings: microphones)
        let modelLibrary = ModelLibraryViewModel()
        let history = TranscriptHistoryViewModel()
        let localLearning = LocalLearningViewModel()
        let customVocabulary = CustomVocabularyViewModel()
        let excludedApplications = ExcludedApplicationsViewModel()
        let overlayModel = RecordingOverlayModel()
        let recordingFeedback = RecordingFeedbackController()
        let recordingAudioOptions = RecordingAudioOptionsController()
        self.dictation = dictation
        self.modelLibrary = modelLibrary
        self.history = history
        self.localLearning = localLearning
        self.customVocabulary = customVocabulary
        self.excludedApplications = excludedApplications
        self.microphones = microphones
        self.overlayModel = overlayModel
        self.recordingFeedback = recordingFeedback
        self.recordingAudioOptions = recordingAudioOptions
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
        hotkey.onStartRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.startRecording()
            }
        }
        hotkey.onStopRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stopAndDeliverRecording()
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
        guard let catalog = modelLibrary.catalog else {
            dictation.errorMessage = modelLibrary.startupError ?? "The speech model catalog is unavailable."
            return
        }
        let engineID = modelLibrary.selectedEngineID
        let backend = TranscriptionBackend.resolve(
            engineID: engineID,
            catalog: catalog,
            installedDownloadIDs: modelLibrary.installedDownloadIDs
        )
        if case .unavailable(let unavailableEngineID) = backend {
            dictation.errorMessage = "The selected transcription engine is unavailable: \(unavailableEngineID)."
            return
        }
        let modelDirectory = modelLibrary.installedModelDirectory(for: engineID)
        if backend == .appleSpeech, !dictation.assetsPrepared {
            dictation.errorMessage = "Prepare Apple Speech in EchoType before recording with Apple Speech."
            return
        }
        if backend != .appleSpeech, modelDirectory == nil {
            dictation.errorMessage = "The selected local model is not installed or failed verification. Reinstall it from Speech Models."
            return
        }
        dismissOverlayTask?.cancel()
        deliveryMessage = nil
        capturedInsertionTarget = textInsertion.captureTarget()
        let languageIdentifier = UserDefaults.standard.string(forKey: "EchoType.transcriptionLanguage")
            ?? Locale.current.identifier
        let vocabularyTerms = TranscriptionVocabulary.terms(
            customTerms: customVocabulary.store.terms.map(\.term),
            learnedTerms: localLearning.store.learnedTerms
        )
        await dictation.startRecording(
            backend: backend,
            modelDirectory: modelDirectory,
            languageIdentifier: languageIdentifier,
            vocabularyTerms: vocabularyTerms,
            ctcVocabularyDirectory: backend == .parakeetV3
                ? modelLibrary.installedModelDirectory(
                    forDownloadID: ModelLibraryViewModel.parakeetVocabularyDownloadID
                )
                : nil
        )
        if dictation.isRecording {
            recordingStartedAt = Date()
            recordingEngineID = engineID
            recordingAudioOptions.startRecording()
            recordingFeedback.recordingStarted()
        } else {
            capturedInsertionTarget = nil
        }
    }

    func toggleRecording() async {
        if dictation.isRecording {
            await stopAndDeliverRecording()
            return
        }
        guard !dictation.isTranscribing else { return }
        await startRecording()
    }

    func stopAndDeliverRecording() async {
        guard dictation.isRecording else { return }
        if textInsertion.isFrontmostAppExcluded() {
            await discardRecordingInExcludedApp()
            recordingStartedAt = nil
            recordingEngineID = nil
            return
        }
        isDeliveringTranscript = true
        overlayModel.phase = .finishing
        overlayWindow.show()
        recordingAudioOptions.stopRecording()
        recordingFeedback.recordingStopped()
        await dictation.stopAndTranscribe(saveAudio: history.settings.historyEnabled && history.settings.saveAudio)
        let duration = max(0, Date().timeIntervalSince(recordingStartedAt ?? Date()))
        recordingStartedAt = nil
        let audioData = dictation.takeCompletedRecordingAudioData()
        if !dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try history.saveTranscript(
                    dictation.transcript,
                    duration: duration,
                    modelID: recordingEngineID ?? modelLibrary.selectedEngineID,
                    audioData: audioData
                )
            } catch {
                history.errorMessage = "Transcript was recognized but history could not be saved: \(error.localizedDescription)"
            }
        }
        recordingEngineID = nil
        guard !dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            deliveryMessage = dictation.errorMessage ?? "No speech was recognized; nothing was inserted."
            capturedInsertionTarget = nil
            isDeliveringTranscript = false
            synchronizeOverlay(with: dictation)
            return
        }
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
    }

    private func discardRecordingInExcludedApp() async {
        recordingAudioOptions.stopRecording()
        recordingFeedback.recordingStopped()
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
