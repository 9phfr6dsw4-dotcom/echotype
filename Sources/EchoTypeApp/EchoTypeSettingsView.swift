import AppKit
import EchoTypeCore
import SwiftUI
import UniformTypeIdentifiers

struct EchoTypeSettingsView: View {
    @Environment(EchoTypeRuntime.self) private var runtime
    @State private var showingClearConfirmation = false
    @AppStorage("EchoType.showLiveWords") private var showLiveWords = true
    @AppStorage(RecordingFeedbackController.dockIconPreferenceKey) private var changeDockIconWhileRecording = false
    @AppStorage(RecordingFeedbackController.soundsPreferenceKey) private var playRecordingSounds = false
    @AppStorage(TextInsertionService.correctionLearningPreferenceKey) private var learnRecentInsertionCorrections = false
    @AppStorage("EchoType.transcriptionLanguage") private var transcriptionLanguage = ""
    @State private var newVocabularyTerm = ""
    @State private var vocabularyDrafts: [UUID: String] = [:]

    private var history: TranscriptHistoryViewModel { runtime.history }
    private var excludedApps: ExcludedApplicationsViewModel { runtime.excludedApplications }
    private var microphones: MicrophoneSettingsViewModel { runtime.microphones }
    private var learning: LocalLearningViewModel { runtime.localLearning }
    private var vocabulary: CustomVocabularyViewModel { runtime.customVocabulary }
    private var modelLibrary: ModelLibraryViewModel { runtime.modelLibrary }
    private var recordingAudioOptions: RecordingAudioOptionsController { runtime.recordingAudioOptions }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.largeTitle.weight(.semibold))
                    Text("Keep control over local data and where EchoType can dictate.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                historySettings
                microphoneSettings
                transcriptionLanguageSettings
                excludedApplicationsSettings
                localLearningSettings
                customVocabularySettings
                recordingBehaviorSettings
                recordingAudioSettings

                Label("Speech and transcripts stay on this Mac. EchoType does not use accounts, analytics, or cloud transcription.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Clear all EchoType transcript data?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Transcript Data", role: .destructive) {
                do {
                    try history.clearAll()
                } catch {
                    history.errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes EchoType transcript history and audio recordings, but does not delete Markdown archive files in your chosen folder or learned words. Files outside EchoType's transcript store are kept.")
        }
        .onAppear {
            runtime.overlayModel.showLiveWords = showLiveWords
            runtime.recordingFeedback.setDockIconChangeEnabled(changeDockIconWhileRecording)
            runtime.textInsertion.setCorrectionLearningEnabled(learnRecentInsertionCorrections)
        }
        .onChange(of: showLiveWords) { _, enabled in
            runtime.overlayModel.showLiveWords = enabled
        }
        .onChange(of: changeDockIconWhileRecording) { _, enabled in
            runtime.recordingFeedback.setDockIconChangeEnabled(enabled)
        }
        .onChange(of: learnRecentInsertionCorrections) { _, enabled in
            runtime.textInsertion.setCorrectionLearningEnabled(enabled)
        }
        .frame(minWidth: 760, minHeight: 580)
    }

    private var historySettings: some View {
        GroupBox("Transcript history and storage") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Keep transcript history on this Mac", isOn: setting(\.historyEnabled))
                Picker("Delete transcripts after", selection: setting(\.retention)) {
                    Text("7 days").tag(TranscriptHistoryRetention.sevenDays)
                    Text("30 days").tag(TranscriptHistoryRetention.thirtyDays)
                    Text("90 days").tag(TranscriptHistoryRetention.ninetyDays)
                    Text("Forever").tag(TranscriptHistoryRetention.forever)
                }
                .disabled(!history.settings.historyEnabled)
                Toggle("Save audio recordings (off by default)", isOn: setting(\.saveAudio))
                    .disabled(!history.settings.historyEnabled)
                Text("Audio is saved only with history enabled and is removed by the same retention policy. Learned words are stored separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Archive each transcript as Markdown", isOn: Binding(
                    get: { history.archiveDirectoryPath != nil },
                    set: { enabled in
                        if enabled { chooseArchiveDirectory() }
                        else { history.archiveDirectoryPath = nil }
                    }
                ))
                Text("Markdown archiving is independent of local history and retention. When a folder is selected, each recognized transcript is archived there even if local history is off; clearing EchoType history does not delete those archive files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let path = history.archiveDirectoryPath {
                    HStack {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Choose Folder…", action: chooseArchiveDirectory)
                    }
                }

                HStack {
                    Button("Clear All Data…", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    Spacer()
                    Text("\(history.records.count) saved transcripts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = history.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var supportedPinnedLanguages: [SupportedLanguage] {
        guard let catalog = modelLibrary.catalog,
              let engine = catalog.engine(id: ModelSelection.parakeetEngineID) else {
            return []
        }
        return engine.supportedLanguages.sorted { $0.name < $1.name }
    }

    private var transcriptionLanguageSettings: some View {
        GroupBox("Transcription language") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Preferred language", selection: $transcriptionLanguage) {
                    Text("Automatic (current Mac language)").tag("")
                    if !transcriptionLanguage.isEmpty,
                       !supportedPinnedLanguages.contains(where: { $0.code == transcriptionLanguage }) {
                        Text("Other — \(transcriptionLanguage)").tag(transcriptionLanguage)
                    }
                    ForEach(supportedPinnedLanguages) { language in
                        Text("\(language.name) (\(language.code))").tag(language.code)
                    }
                }
                Text("The pinned language is passed to the selected engine. The list shows Parakeet v3's supported languages; Automatic uses your Mac's current language for Apple Speech and Whisper. If Parakeet cannot support the selected or automatic language, EchoType shows an error instead of silently switching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var excludedApplicationsSettings: some View {
        GroupBox("Excluded apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text("EchoType will not record or insert text while an excluded app is active. Password managers are excluded by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                List {
                    Section("Always excluded") {
                        ForEach(excludedApps.policy.defaultExcludedApplications, id: \.bundleIdentifier) { app in
                            Label(app.displayName, systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Your exclusions") {
                        if excludedApps.policy.userExcludedApplications.isEmpty {
                            Text("No additional apps excluded")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(excludedApps.policy.userExcludedApplications, id: \.bundleIdentifier) { app in
                            HStack {
                                Label(app.displayName, systemImage: "app.badge")
                                Spacer()
                                Button("Remove") {
                                    excludedApps.removeApplication(bundleIdentifier: app.bundleIdentifier)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(minHeight: 170, maxHeight: 260)

                HStack {
                    Button("Add Installed App…", action: chooseExcludedApplication)
                    Spacer()
                }
                if let errorMessage = excludedApps.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var localLearningSettings: some View {
        GroupBox("Local learning") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Learn corrections made to recent EchoType insertions",
                    isOn: $learnRecentInsertionCorrections
                )
                Text("Off by default. When enabled, EchoType watches the same field it just pasted into for up to 10 seconds. It considers only a selected range wholly inside that insertion, waits 800 ms after a value change, and reads only the validated replacement range. It never reads whole-field text, window titles, URLs, secure fields, or excluded apps. If Accessibility range, notification, or target checks are unavailable or ambiguous, nothing is learned. Accepted one-word corrections use the existing local-learning rule and need at least three repeats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Ask me before adding learned words", isOn: Binding(
                    get: { learning.askBeforeAdding },
                    set: { learning.askBeforeAdding = $0 }
                ))
                Text("EchoType learns only from explicit corrections you save in transcript history. The same correction must appear at least three times; short common words are ignored. Learned words stay on this Mac and are kept when transcript history is cleared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !learning.store.pendingAdditions.isEmpty {
                    Divider()
                    Text("Needs your confirmation")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(learning.store.pendingAdditions.enumerated()), id: \.offset) { entry in
                        let item = entry.element
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.term).font(.body.weight(.medium))
                                Text("Correction: \(item.original) → \(item.term) · \(item.occurrenceCount) times")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { _ = learning.confirmAddition(of: item.term) }
                            Button("Ignore", role: .destructive) { _ = learning.rejectAddition(of: item.term) }
                        }
                    }
                }

                Divider()
                HStack {
                    Text("Learned words")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(learning.store.learnedTerms.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if learning.store.learnedTerms.isEmpty {
                    Text("No learned words yet. Correct and save a transcript to teach EchoType.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(learning.store.learnedTerms) { term in
                        HStack {
                            Text(term.term)
                            Text("· \(term.occurrenceCount) corrections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(term.isPinned ? "Unpin" : "Pin") {
                                _ = learning.setPinned(!term.isPinned, for: term.term)
                            }
                            Button("Remove", role: .destructive) {
                                _ = learning.removeLearnedTerm(term.term)
                            }
                        }
                    }
                }

                if let errorMessage = learning.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var parakeetVocabularyStatus: some View {
        let isAvailable = modelLibrary.optionalDownload(forEngineID: ModelSelection.parakeetEngineID) != nil
        let isInstalled = modelLibrary.isParakeetVocabularyInstalled
        let isDownloading = modelLibrary.isParakeetVocabularyDownloading
        let progress = modelLibrary.parakeetVocabularyProgress
        let parakeetInstalled = modelLibrary.isParakeetInstalled

        return VStack(alignment: .leading, spacing: 6) {
            if !isAvailable {
                Label("Parakeet CTC companion status unavailable.", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    modelLibrary.parakeetVocabularyStatus,
                    systemImage: isInstalled ? "checkmark.circle.fill" : isDownloading ? "arrow.down.circle" : "info.circle"
                )
                .foregroundStyle(isInstalled ? .green : .secondary)
                .textSelection(.enabled)
            }

            if isDownloading, let progress {
                ProgressView(
                    value: Double(progress.verifiedBytes),
                    total: Double(max(progress.totalBytes, 1))
                )
                Text("Verified \(progress.verifiedFileCount) of \(progress.fileCount) companion files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isInstalled, !isDownloading, parakeetInstalled {
                Button("Retry vocabulary add-on download") {
                    Task { await modelLibrary.ensureParakeetVocabularyCompanionForCustomTerms() }
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage = modelLibrary.parakeetVocabularyErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .font(.caption)
    }

    private var customVocabularySettings: some View {
        GroupBox("Custom vocabulary") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add names and unusual words to bias supported local speech engines. Apple Speech uses up to 100 contextual phrases; Whisper uses decoder prompt tokens. Parakeet's optional 2.37 GB CTC companion is included in an explicit Parakeet download (the combined size is shown first), or downloaded when you add a custom term if Parakeet is already installed. Missing or failed companion downloads disable only custom-vocabulary rescoring; base Parakeet transcripts continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                parakeetVocabularyStatus

                HStack {
                    TextField("Name or unusual word", text: $newVocabularyTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addVocabularyTerm)
                    Button("Add", action: addVocabularyTerm)
                        .disabled(!vocabulary.canMutate || newVocabularyTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if vocabulary.store.terms.isEmpty {
                    Text("No custom terms yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vocabulary.store.terms) { term in
                        HStack(spacing: 8) {
                            TextField("Vocabulary term", text: vocabularyBinding(for: term))
                                .textFieldStyle(.roundedBorder)
                                .disabled(!vocabulary.canMutate)
                            Button("Save") { saveVocabularyTerm(term) }
                                .disabled(!vocabulary.canMutate)
                            Button("Remove", role: .destructive) { removeVocabularyTerm(term) }
                                .disabled(!vocabulary.canMutate)
                        }
                    }
                }

                if let errorMessage = vocabulary.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var recordingBehaviorSettings: some View {
        GroupBox("Recording behavior") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show live words in the recording overlay", isOn: $showLiveWords)
                Toggle("Change the Dock icon while recording", isOn: $changeDockIconWhileRecording)
                Toggle("Play optional recording start/stop sounds", isOn: $playRecordingSounds)
                Toggle("Keep microphone on between recordings (instant-on)", isOn: .constant(false))
                    .disabled(true)
                    .accessibilityHint("Unavailable in this build; EchoType never leaves the microphone active between recordings.")
                Text("These cues are off by default. The overlay can show only a recording indicator when live words are hidden; temporary audio is still deleted after transcription unless audio saving is enabled above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var recordingAudioSettings: some View {
        GroupBox("Media and output volume") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Pause Music and Spotify while recording", isOn: Binding(
                    get: { recordingAudioOptions.pauseSupportedPlayersWhenRecording },
                    set: { recordingAudioOptions.pauseSupportedPlayersWhenRecording = $0 }
                ))
                Toggle("Lower system output volume while recording", isOn: Binding(
                    get: { recordingAudioOptions.lowerOutputVolumeWhenRecording },
                    set: { recordingAudioOptions.lowerOutputVolumeWhenRecording = $0 }
                ))
                HStack {
                    Text("Reduce by \(Int(recordingAudioOptions.outputVolumeReductionPercent))%")
                        .frame(width: 115, alignment: .leading)
                    Slider(value: Binding(
                        get: { recordingAudioOptions.outputVolumeReductionPercent },
                        set: { recordingAudioOptions.outputVolumeReductionPercent = $0 }
                    ), in: 0...100, step: 5)
                    .disabled(!recordingAudioOptions.lowerOutputVolumeWhenRecording)
                }

                Text("Media controls are optional and may require macOS Automation permission. Only Music and Spotify are controlled; browser media is not. EchoType restores the saved output volume when recording ends. Instant-on microphone is unavailable in this build, so EchoType never leaves it active between sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recordingAudioOptions.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var microphoneSettings: some View {
        GroupBox("Microphones") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Input", selection: Binding(
                    get: { microphones.pickerSelection },
                    set: { microphones.setPickerSelection($0) }
                )) {
                    Text("Automatic (priority order)").tag(MicrophoneSettingsViewModel.automaticSelection)
                    ForEach(microphones.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                HStack {
                    Text("Ready now: \(microphones.currentReadyDevice?.name ?? "No microphone ready")")
                        .font(.caption)
                        .foregroundStyle(microphones.currentReadyDevice == nil ? .red : .secondary)
                    Spacer()
                    Button("Refresh") { microphones.refreshDevices() }
                }

                if microphones.orderedDevices.isEmpty {
                    Text("Connect or enable a microphone to see it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(microphones.orderedDevices) { device in
                            let index = microphones.priorityDeviceIDs.firstIndex(of: device.id) ?? 0
                            HStack {
                                Text(device.name)
                                Spacer()
                                if device.id == microphones.currentReadyDevice?.id {
                                    Label("Ready", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                Button {
                                    microphones.movePriority(id: device.id, direction: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                .accessibilityLabel("Move \(device.name) up")
                                Button {
                                    microphones.movePriority(id: device.id, direction: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == microphones.orderedDevices.count - 1)
                                .accessibilityLabel("Move \(device.name) down")
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: 190)
                }

                Text("Automatic follows this order and appends newly discovered microphones at the bottom. A directly selected device falls back safely if it is disconnected or disallowed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if microphones.isLidClosed {
                    Label("Closed-lid mode is active; the built-in MacBook microphone is skipped.", systemImage: "laptopcomputer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = microphones.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear { microphones.refreshDevices() }
    }

    private func addVocabularyTerm() {
        do {
            _ = try vocabulary.addTerm(newVocabularyTerm)
            newVocabularyTerm = ""
            Task { await runtime.modelLibrary.ensureParakeetVocabularyCompanionForCustomTerms() }
        } catch {
            // The view model exposes a local, user-readable error message.
        }
    }

    private func vocabularyBinding(for term: CustomVocabularyTerm) -> Binding<String> {
        Binding(
            get: { vocabularyDrafts[term.id] ?? term.term },
            set: { vocabularyDrafts[term.id] = $0 }
        )
    }

    private func saveVocabularyTerm(_ term: CustomVocabularyTerm) {
        guard let draft = vocabularyDrafts[term.id] else { return }
        do {
            _ = try vocabulary.editTerm(id: term.id, to: draft)
            vocabularyDrafts.removeValue(forKey: term.id)
            Task { await runtime.modelLibrary.ensureParakeetVocabularyCompanionForCustomTerms() }
        } catch {
            // The view model exposes a local, user-readable error message.
        }
    }

    private func removeVocabularyTerm(_ term: CustomVocabularyTerm) {
        do {
            _ = try vocabulary.removeTerm(id: term.id)
            vocabularyDrafts.removeValue(forKey: term.id)
        } catch {
            // The view model exposes a local, user-readable error message.
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<TranscriptHistorySettings, Value>) -> Binding<Value> {
        Binding(
            get: { history.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = history.settings
                updated[keyPath: keyPath] = newValue
                history.settings = updated
            }
        )
    }

    private func chooseArchiveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Transcript Archive Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let current = history.archiveDirectoryPath {
            panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        history.archiveDirectoryPath = url.path
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Installed App to Exclude"
        panel.prompt = "Exclude App"
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            excludedApps.addApplication(at: url)
        }
    }
}
