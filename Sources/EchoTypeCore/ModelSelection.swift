import Foundation

public struct ModelSelection: Equatable, Sendable {
    public static let appleSpeechEngineID = "apple-speech"

    public private(set) var engineID: String

    public init(
        catalog: ModelCatalog,
        preferredEngineID: String? = nil,
        installedDownloadIDs: Set<String> = []
    ) {
        let preferred = preferredEngineID.flatMap { id -> String? in
            guard let engine = catalog.engine(id: id) else { return nil }
            guard let downloadID = engine.downloadId else { return id }
            return installedDownloadIDs.contains(downloadID) ? id : nil
        }
        let fallback = catalog.engine(id: Self.appleSpeechEngineID)?.id
            ?? catalog.engines.first(where: { engine in
                guard let downloadID = engine.downloadId else { return true }
                return installedDownloadIDs.contains(downloadID)
            })?.id
            ?? catalog.engines.first?.id
            ?? Self.appleSpeechEngineID
        self.engineID = preferred ?? fallback
    }

    @discardableResult
    public mutating func select(
        engineID: String,
        catalog: ModelCatalog,
        installedDownloadIDs: Set<String>
    ) -> Bool {
        guard let engine = catalog.engine(id: engineID) else { return false }
        if let downloadID = engine.downloadId, !installedDownloadIDs.contains(downloadID) {
            return false
        }
        self.engineID = engineID
        return true
    }
}
