import EchoTypeCore
import Foundation
import Observation

@MainActor
@Observable
final class ModelLibraryViewModel {
    private(set) var catalog: ModelCatalog?
    private(set) var startupError: String?
    private(set) var selectedEngineID = ModelSelection.appleSpeechEngineID
    private(set) var installedDownloadIDs: Set<String> = []
    private(set) var activeDownloadIDs: Set<String> = []
    private(set) var progressByDownloadID: [String: ModelInstallProgress] = [:]
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let installer: ModelArtifactInstaller
    @ObservationIgnored private let fluidAudioInstaller: ModelArtifactInstaller
    private var selection: ModelSelection?

    static let parakeetVocabularyDownloadID = "parakeet-ctc-0.6b-coreml"
    private static let selectedEngineDefaultsKey = "EchoType.selectedEngineID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.installer = ModelArtifactInstaller(modelsDirectory: Self.modelsDirectory())
        self.fluidAudioInstaller = ModelArtifactInstaller(modelsDirectory: Self.fluidAudioModelsDirectory())

        do {
            let catalog = try ModelCatalog.bundled()
            self.catalog = catalog
            let installed = Set(catalog.downloads.compactMap { download -> String? in
                guard Self.installer(for: download, standard: installer, fluidAudio: fluidAudioInstaller)
                    .isInstalled(download) else { return nil }
                return download.id
            })
            self.installedDownloadIDs = installed
            let selection = ModelSelection(
                catalog: catalog,
                preferredEngineID: defaults.string(forKey: Self.selectedEngineDefaultsKey),
                installedDownloadIDs: installed
            )
            self.selection = selection
            self.selectedEngineID = selection.engineID
        } catch {
            self.startupError = error.localizedDescription
        }
    }

    func isReady(_ engine: ModelEngine) -> Bool {
        guard let downloadId = engine.downloadId else { return true }
        return installedDownloadIDs.contains(downloadId)
    }

    func installedModelDirectory(for engineID: String) -> URL? {
        guard let catalog,
              let download = catalog.download(forEngineID: engineID) else { return nil }
        return installer(for: download).installedURL(for: download)
    }

    func installedModelDirectory(forDownloadID downloadID: String) -> URL? {
        guard let download = catalog?.download(id: downloadID),
              installedDownloadIDs.contains(downloadID) else { return nil }
        return installer(for: download).installedURL(for: download)
    }

    func download(for engine: ModelEngine) -> ModelDownload? {
        guard let downloadID = engine.downloadId else { return nil }
        return catalog?.download(id: downloadID)
    }

    func optionalDownload(forEngineID engineID: String) -> ModelDownload? {
        catalog?.downloads.first { $0.engineId == engineID && $0.optional }
    }

    func select(engineID: String) {
        guard let catalog,
              selection?.select(engineID: engineID, catalog: catalog, installedDownloadIDs: installedDownloadIDs) == true,
              let selection else { return }
        selectedEngineID = selection.engineID
        defaults.set(selection.engineID, forKey: Self.selectedEngineDefaultsKey)
        errorMessage = nil
    }

    func download(engineID: String) async {
        guard let catalog,
              let engine = catalog.engine(id: engineID),
              let artifact = download(for: engine) else { return }
        await download(downloadID: artifact.id)
    }

    func download(downloadID: String) async {
        guard let download = catalog?.download(id: downloadID),
              !installedDownloadIDs.contains(download.id),
              activeDownloadIDs.insert(download.id).inserted else { return }

        let downloadInstaller = installer(for: download)
        errorMessage = nil
        defer {
            activeDownloadIDs.remove(downloadID)
            progressByDownloadID.removeValue(forKey: downloadID)
        }

        do {
            _ = try await downloadInstaller.install(download) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.progressByDownloadID[downloadID] = progress
                }
            }
            installedDownloadIDs.insert(downloadID)
            refreshSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(engineID: String) throws {
        guard let catalog,
              let engine = catalog.engine(id: engineID),
              let download = download(for: engine) else { return }
        if selectedEngineID == engineID {
            select(engineID: ModelSelection.appleSpeechEngineID)
        }
        try remove(downloadID: download.id)
    }

    func remove(downloadID: String) throws {
        guard let catalog,
              let download = catalog.download(id: downloadID) else { return }
        if let engine = catalog.engine(id: download.engineId),
           engine.downloadId == download.id,
           selectedEngineID == engine.id {
            select(engineID: ModelSelection.appleSpeechEngineID)
        }
        if try installer(for: download).removeInstalled(download) {
            installedDownloadIDs.remove(download.id)
        }
    }

    private func installer(for download: ModelDownload) -> ModelArtifactInstaller {
        Self.installer(for: download, standard: installer, fluidAudio: fluidAudioInstaller)
    }

    private static func installer(
        for download: ModelDownload,
        standard: ModelArtifactInstaller,
        fluidAudio: ModelArtifactInstaller
    ) -> ModelArtifactInstaller {
        download.id == parakeetVocabularyDownloadID ? fluidAudio : standard
    }

    private static func modelsDirectory() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportDirectory.appendingPathComponent("EchoType/Models", isDirectory: true)
    }

    private static func fluidAudioModelsDirectory() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportDirectory.appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    private func refreshSelection() {
        guard let catalog else { return }
        let updated = ModelSelection(
            catalog: catalog,
            preferredEngineID: defaults.string(forKey: Self.selectedEngineDefaultsKey),
            installedDownloadIDs: installedDownloadIDs
        )
        selection = updated
        selectedEngineID = updated.engineID
    }
}
