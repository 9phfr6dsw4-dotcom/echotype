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
    var deliveryDebugInfo: String?

    var preferredTranscriptionLanguageIdentifier: String {
        TranscriptionLanguagePreference.resolve(
            UserDefaults.standard.string(forKey: "EchoType.transcriptionLanguage"),
            systemLanguageIdentifier: Locale.current.identifier
        )
    }

    @ObservationIgnored private let overlayWindow: RecordingOverlayWindowController
    @ObservationIgnored private var dismissOverlayTask: Task<Void, Never>?
    @ObservationIgnored private var workspaceActivationObserver: NSObjectProtocol?
    @ObservationIgnored private var recordingStartGate = RecordingStartGate()
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

        textInsertion.onTranscriptCorrection = { [weak localLearning] original, corrected in
            localLearning?.observeTranscriptCorrection(original: original, corrected: corrected)
        }

        dictation.onChange = { [weak self] state in
            self?.synchronizeOverlay(with: state)
        }
        hotkey.onToggleRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.toggleRecording()
            }
        }
        hotkey.onStartRecording = { [weak self] in
            self?.startHotkeyRecording()
        }
        hotkey.onStopRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stopOrCancelHotkeyRecording()
            }
        }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hotkey.refreshPermission()
                self.textInsertion.cancelCorrectionObservationIfTargetIsInvalid()
                guard self.dictation.isRecording,
                      self.textInsertion.isFrontmostAppExcluded() else { return }
                await self.discardRecordingInExcludedApp()
            }
        }
        hotkey.refreshPermission()
    }

    private func startHotkeyRecording() {
        guard let startToken = recordingStartGate.begin() else { return }
        Task { @MainActor [weak self] in
            await self?.startRecording(startToken: startToken)
        }
    }

    func startRecording() async {
        guard let startToken = recordingStartGate.begin() else { return }
        await startRecording(startToken: startToken)
    }

    private func startRecording(startToken: UInt64) async {
        defer { recordingStartGate.finish(startToken) }
        guard recordingStartGate.isCurrent(startToken) else { return }

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
        let languageIdentifier = preferredTranscriptionLanguageIdentifier
        if backend == .appleSpeech {
            await dictation.checkAppleSpeechAssets(localeIdentifier: languageIdentifier)
            guard recordingStartGate.isCurrent(startToken) else { return }
            guard dictation.isAppleSpeechPrepared(for: languageIdentifier) else {
                dictation.errorMessage = dictation.errorMessage
                    ?? "Apple Speech assets aren't installed for this language yet. Choose Prepare Apple Speech in the Dictation panel, then use the hotkey again."
                return
            }
        }
        if backend != .appleSpeech, modelDirectory == nil {
            dictation.errorMessage = "The selected local model is not installed or failed verification. Reinstall it from Speech Models."
            return
        }
        dismissOverlayTask?.cancel()
        deliveryMessage = nil
        deliveryDebugInfo = nil
        overlayModel.deliveryMessage = nil
        overlayModel.deliveryDebugInfo = nil
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
        guard recordingStartGate.isCurrent(startToken) else {
            if dictation.isRecording {
                await dictation.cancelAndDiscardRecording()
                overlayModel.phase = .idle
                overlayWindow.hide()
                deliveryMessage = "Dictation start was canceled before audio setup finished."
            }
            return
        }
        if dictation.isRecording {
            recordingStartedAt = Date()
            recordingEngineID = engineID
            recordingAudioOptions.startRecording()
            recordingFeedback.recordingStarted()
        }
    }

    private func cancelPendingRecordingStart() async -> Bool {
        guard recordingStartGate.cancelPending() else { return false }
        if dictation.isRecording {
            await dictation.cancelAndDiscardRecording()
            overlayModel.phase = .idle
            overlayWindow.hide()
        }
        deliveryMessage = "Dictation start canceled because the hotkey was released before setup finished."
        return true
    }

    private func stopOrCancelHotkeyRecording() async {
        if await cancelPendingRecordingStart() { return }
        await stopAndDeliverRecording()
    }

    func toggleRecording() async {
        if dictation.isRecording {
            if await cancelPendingRecordingStart() { return }
            await stopAndDeliverRecording()
            return
        }
        if await cancelPendingRecordingStart() { return }
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
        let insertionTargetAtStop = textInsertion.captureDeliveryTarget()
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
            isDeliveringTranscript = false
            synchronizeOverlay(with: dictation)
            return
        }
        let report = await textInsertion.deliver(
            dictation.transcript,
            capturedTarget: insertionTargetAtStop,
            copyToClipboard: UserDefaults.standard.bool(forKey: "EchoType.copyToClipboard"),
            autoSend: UserDefaults.standard.bool(forKey: "EchoType.autoSend")
        )
        let pasteSummary = Self.message(for: report.outcome)
        deliveryMessage = report.clipboardRestorationWarning.map {
            "\(pasteSummary) \($0)"
        } ?? pasteSummary
        deliveryDebugInfo = report.debugInfo
        overlayModel.deliveryMessage = report.needsDeliveryNotice ? deliveryMessage : nil
        overlayModel.deliveryDebugInfo = report.needsDeliveryNotice ? report.debugInfo : nil
        isDeliveringTranscript = false
        synchronizeOverlay(with: dictation)
    }

    private func discardRecordingInExcludedApp() async {
        recordingAudioOptions.stopRecording()
        recordingFeedback.recordingStopped()
        let target = textInsertion.captureDeliveryTarget()
        await dictation.cancelAndDiscardRecording()
        recordingStartedAt = nil
        recordingEngineID = nil
        deliveryMessage = "Not pasted: dictation was discarded because an excluded app became active."
        let appName = target?.snapshot.applicationName ?? "Unknown"
        let focusType = target?.focusedElementType ?? "Unavailable (no frontmost application)"
        deliveryDebugInfo = "Frontmost app: \(appName)\nFocused element type: \(focusType)\nPaste skipped: Dictation was discarded before transcription because an excluded app became active."
        overlayModel.phase = .done
        overlayModel.deliveryMessage = deliveryMessage
        overlayModel.deliveryDebugInfo = deliveryDebugInfo
        overlayWindow.show()
        dismissOverlayTask?.cancel()
        dismissOverlayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.overlayWindow.hide()
        }
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
                let hideDelay: Duration = overlayModel.deliveryMessage == nil ? .milliseconds(1200) : .seconds(5)
                try? await Task.sleep(for: hideDelay)
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
            "Command-V was sent to the verified text field; EchoType cannot confirm whether the app accepted it."
        case .insertedViaSameApplicationFallback:
            "Command-V was sent because the same app remained in front; EchoType cannot confirm whether the app accepted it."
        case .insertedAndSubmitted:
            "Command-V and Return were sent to the verified text field; EchoType cannot confirm whether the app accepted them."
        case .copyOnly(.targetUnavailable):
            "Not pasted: EchoType could not verify the foreground app when dictation stopped and text was ready. Use Copy in the transcript."
        case .copyOnly(.targetChanged):
            "Not pasted: the foreground app changed before the text was ready. Use Copy in the transcript."
        case .copyOnly(.excludedApplication):
            "Not pasted in an excluded application."
        case .copyOnly(.secureField):
            "Not pasted: the focused control is marked as a secure field. Use Copy only if you intend to place the transcript there."
        case .failed:
            "Text could not be pasted. The transcript remains available in EchoType."
        }
    }
}
