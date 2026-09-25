import Foundation

/// Produces the user-initiated download set for an engine installation.
/// Parakeet's base model remains independently usable if its vocabulary
/// companion is unavailable; the companion only adds contextual rescoring.
public enum ModelDownloadPlan {
    public static let parakeetVocabularyDownloadID = "parakeet-ctc-0.6b-coreml"

    public static func downloadsForExplicitInstall(
        engineID: String,
        catalog: ModelCatalog,
        installedDownloadIDs: Set<String>
    ) -> [ModelDownload] {
        guard let engine = catalog.engine(id: engineID) else { return [] }

        var downloadIDs: [String] = []
        if let baseID = engine.downloadId {
            downloadIDs.append(baseID)
        }
        if engineID == ModelSelection.parakeetEngineID {
            downloadIDs.append(parakeetVocabularyDownloadID)
        }

        var seen = Set<String>()
        return downloadIDs.compactMap { id in
            guard seen.insert(id).inserted,
                  !installedDownloadIDs.contains(id) else { return nil }
            return catalog.download(id: id)
        }
    }

    public static func totalBytes(_ downloads: [ModelDownload]) -> Int {
        downloads.reduce(0) { partial, download in
            let (total, overflow) = partial.addingReportingOverflow(download.bytes)
            return overflow ? Int.max : total
        }
    }
}
