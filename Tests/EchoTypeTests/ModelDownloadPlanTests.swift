import XCTest
@testable import EchoTypeCore

final class ModelDownloadPlanTests: XCTestCase {
    func testFirstParakeetDownloadIncludesModelAndVocabularyCompanionInTotal() throws {
        let catalog = try ModelCatalogTestSupport.catalog()
        let downloads = ModelDownloadPlan.downloadsForExplicitInstall(
            engineID: ModelSelection.parakeetEngineID,
            catalog: catalog,
            installedDownloadIDs: []
        )

        XCTAssertEqual(downloads.map(\.id), ["parakeet-v3", "parakeet-ctc-0.6b-coreml"])
        XCTAssertEqual(ModelDownloadPlan.totalBytes(downloads), 3_006_356_230)
    }

    func testParakeetDownloadDoesNotRedownloadAlreadyInstalledCompanion() throws {
        let catalog = try ModelCatalogTestSupport.catalog()

        let downloads = ModelDownloadPlan.downloadsForExplicitInstall(
            engineID: ModelSelection.parakeetEngineID,
            catalog: catalog,
            installedDownloadIDs: ["parakeet-ctc-0.6b-coreml"]
        )

        XCTAssertEqual(downloads.map(\.id), ["parakeet-v3"])
    }

    func testOtherEngineInstallPlanDoesNotIncludeParakeetCompanion() throws {
        let catalog = try ModelCatalogTestSupport.catalog()

        let downloads = ModelDownloadPlan.downloadsForExplicitInstall(
            engineID: "whisper-large-v3-turbo",
            catalog: catalog,
            installedDownloadIDs: []
        )

        XCTAssertEqual(downloads.map(\.id), ["whisper-large-v3-turbo"])
    }
}
