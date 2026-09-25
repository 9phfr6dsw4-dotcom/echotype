import AppKit
import EchoTypeCore
import SwiftUI
import UniformTypeIdentifiers

struct EchoTypeSettingsView: View {
    @Environment(EchoTypeRuntime.self) private var runtime
    @State private var showingClearConfirmation = false

    private var history: TranscriptHistoryViewModel { runtime.history }
    private var excludedApps: ExcludedApplicationsViewModel { runtime.excludedApplications }
    private var microphones: MicrophoneSettingsViewModel { runtime.microphones }

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
                excludedApplicationsSettings

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
            Text("This removes EchoType transcript history and audio recordings. Learned words and files outside EchoType's transcript store are kept.")
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
                    EditButton()
                }

                if microphones.orderedDevices.isEmpty {
                    Text("Connect or enable a microphone to see it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(microphones.orderedDevices) { device in
                            HStack {
                                Text(device.name)
                                Spacer()
                                if device.id == microphones.currentReadyDevice?.id {
                                    Label("Ready", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .onMove { indices, destination in
                            microphones.movePriority(from: indices, to: destination)
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
