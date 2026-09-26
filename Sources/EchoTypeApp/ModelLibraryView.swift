import AppKit
import EchoTypeCore
import SwiftUI

struct ModelLibraryView: View {
    @Environment(EchoTypeRuntime.self) private var runtime
    @State private var deletionCandidate: ModelEngine?
    @State private var showingDeleteConfirmation = false


    private var library: ModelLibraryViewModel { runtime.modelLibrary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let startupError = library.startupError {
                    ContentUnavailableView(
                        "Model Catalog Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(startupError)
                    )
                } else if let catalog = library.catalog {
                    if let errorMessage = library.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    LazyVStack(spacing: 16) {
                        ForEach(catalog.engines) { engine in
                            modelCard(engine)
                        }
                    }
                } else {
                    ProgressView("Loading model catalog…")
                }

                Label("External models download only after you request them. Parakeet's vocabulary rescoring files are included in its single model installation and removed with it. Apple Speech checks whether system assets are installed; only an explicit Prepare action may install missing Apple assets. Temporary audio is deleted after transcription.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Delete downloaded model?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Model", role: .destructive) {
                guard let engine = deletionCandidate else { return }
                do {
                    try library.remove(engineID: engine.id)
                } catch {
                    library.errorMessage = error.localizedDescription
                }
                deletionCandidate = nil
            }
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
        } message: {
            Text("Remove the verified model files for \(deletionCandidate?.displayName ?? "this model") from this Mac? You can download them again later.")
        }
        .frame(minWidth: 760, minHeight: 580)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speech Models")
                .font(.largeTitle.weight(.semibold))
            Text("Choose an on-device transcription engine. Parakeet and its vocabulary rescoring files are installed and deleted together; every file is checksum-verified.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func modelCard(_ engine: ModelEngine) -> some View {
        let ready = library.isReady(engine)
        let hasInstalledFiles = library.hasInstalledFiles(engineID: engine.id)
        let installationComplete = library.isInstallationComplete(engineID: engine.id)
        let selected = library.selectedEngineID == engine.id
        let download = library.download(for: engine)
        let plannedDownloadBytes = library.initialInstallSize(forEngineID: engine.id)
        let downloading = library.isDownloading(engineID: engine.id)
        let progress = library.downloadProgress(engineID: engine.id)

        return GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(engine.displayName)
                            .font(.title2.weight(.semibold))
                        Label(
                            selected ? "Current engine" : engine.id == ModelSelection.appleSpeechEngineID ? "Available on this Mac" : ready ? "Ready on this Mac" : "Available to download",
                            systemImage: selected ? "checkmark.circle.fill" : ready ? "checkmark.circle" : "arrow.down.circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    }
                    Spacer()
                    if selected {
                        Text("IN USE")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                if let note = engine.accuracyNote {
                    detailRow("Accuracy", note)
                }
                if let note = engine.speedNote {
                    detailRow("Speed", note)
                }
                if let note = engine.vocabularySupport {
                    detailRow("Vocabulary", note)
                }
                detailRow("Languages", languageDescription(for: engine))

                if let download {
                    detailRow("Download", "\(download.bytes.formatted()) bytes · \(download.license ?? "License metadata unavailable")")
                    if engine.id == ModelSelection.parakeetEngineID, !installationComplete {
                        detailRow(
                            "Parakeet install",
                            "\(formattedSize(plannedDownloadBytes)) for the model and vocabulary files not already installed"
                        )
                    }
                    if engine.id == ModelSelection.parakeetEngineID,
                       !ready,
                       library.installedDownloadIDs.contains(ModelDownloadPlan.parakeetVocabularyDownloadID) {
                        detailRow("Already installed", "Parakeet vocabulary files are verified; only missing model files need downloading.")
                    }
                } else if engine.id == ModelSelection.appleSpeechEngineID {
                    detailRow("Speech assets", "Managed by macOS; EchoType checks installation at launch. Choose Prepare Apple Speech to install missing assets.")
                } else {
                    detailRow("Download", "No model download required")
                }

                if downloading {
                    if let progress {
                        ProgressView(value: Double(progress.verifiedBytes), total: Double(max(progress.totalBytes, 1)))
                        Text("Verified \(progress.verifiedFileCount) of \(progress.fileCount) files · \(progress.currentPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        ProgressView("Downloading and verifying…")
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    if selected {
                        Label("Selected", systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                    } else if ready {
                        Button("Use This Model") {
                            library.select(engineID: engine.id)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    if downloading {
                        Button("Downloading…") {}
                            .disabled(true)
                    } else if !installationComplete, let download {
                        Button {
                            Task { await library.download(engineID: engine.id) }
                        } label: {
                            Label(
                                ready ? "Download Missing Files (\(formattedSize(plannedDownloadBytes)))" : "Download (\(formattedSize(plannedDownloadBytes)))",
                                systemImage: "arrow.down.to.line"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if hasInstalledFiles, engine.downloadId != nil {
                        Button(role: .destructive) {
                            deletionCandidate = engine
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Model", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(downloading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }


    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func languageDescription(for engine: ModelEngine) -> String {
        if !engine.supportedLanguages.isEmpty {
            let names = engine.supportedLanguages.map(\.name).joined(separator: ", ")
            return "\(engine.supportedLanguages.count) languages: \(names)"
        }
        return engine.languageSupport
    }
}
