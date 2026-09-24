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
    private var selection: ModelSelection?

    private static let selectedEngineDefaultsKey = "EchoType.selectedEngineID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.installer = ModelArtifactInstaller(modelsDirectory: Self.modelsDirectory())

        do {
            let catalog = try ModelCatalog.bundled()
            self.catalog = catalog
            let installed = Set(catalog.engines.compactMap { engine -> String? in
                guard let downloadID = engine.downloadId,
                      let download = catalog.download(id: downloadID),
                      installer.isInstalled(download) else { return nil }
                return downloadID
            })
            self.installedDownloadIDs = installed
            let selection = ModelSelection(
                catalog: catalog,
                preferredEngineID: defaults.string(forKey: Self.selectedEngineDefaultsKey),
                installedDownloadIDs: installed
            )
            self.selection = selection
            self.selectedEngineID = selection.engineID
            defaults.set(selection.engineID, forKey: Self.selectedEngineDefaultsKey)
        } catch {
            self.startupError = error.localizedDescription
        }
    }

    func isReady(_ engine: ModelEngine) -> Bool {
        guard let downloadID = engine.downloadId else { return true }
        return installedDownloadIDs.contains(downloadID)
    }

    func download(for engine: ModelEngine) -> ModelDownload? {
        guard let downloadID = engine.downloadId else { return nil }
        return catalog?.download(id: downloadID)
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
              let download = download(for: engine),
              !installedDownloadIDs.contains(download.id),
              activeDownloadIDs.insert(download.id).inserted else { return }

        let downloadID = download.id
        errorMessage = nil
        defer {
            activeDownloadIDs.remove(downloadID)
            progressByDownloadID.removeValue(forKey: downloadID)
        }

        do {
            _ = try await installer.install(download) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.progressByDownloadID[downloadID] = progress
                }
            }
            installedDownloadIDs.insert(downloadID)
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
        if try installer.removeInstalled(download) {
            installedDownloadIDs.remove(download.id)
        }
    }

    private static func modelsDirectory() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportDirectory.appendingPathComponent("EchoType/Models", isDirectory: true)
    }
}
