import Foundation
import XCTest
@testable import EchoTypeCore

final class ModelCatalogTests: XCTestCase {
    private func manifestURL() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let packageFile = directory.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageFile.path) {
                return directory.appendingPathComponent("Resources/model-manifest.json")
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "Resources/model-manifest.json")
    }

    private func manifestObject() throws -> [String: Any] {
        let data = try Data(contentsOf: manifestURL())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encoded(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func testCatalogOffersThreeEnginesAndAppleUsesNoModelDownload() throws {
        let catalog = try ModelCatalog(data: Data(contentsOf: manifestURL()))

        XCTAssertEqual(catalog.engines.map(\.id), ["apple-speech", "parakeet-v3", "whisper-large-v3-turbo"])
        XCTAssertNil(catalog.download(forEngineID: "apple-speech"))
        XCTAssertEqual(catalog.download(forEngineID: "parakeet-v3")?.id, "parakeet-v3")
        XCTAssertEqual(catalog.download(forEngineID: "whisper-large-v3-turbo")?.id, "whisper-large-v3-turbo")
    }

    func testParakeetLanguagesAndOptionalVocabularyAreExposedSeparately() throws {
        let catalog = try ModelCatalog(data: Data(contentsOf: manifestURL()))
        let parakeet = try XCTUnwrap(catalog.engine(id: "parakeet-v3"))
        let languages = Set(parakeet.supportedLanguages.map(\.code))

        XCTAssertEqual(parakeet.supportedLanguages.count, 25)
        XCTAssertTrue(languages.contains("en"))
        XCTAssertTrue(languages.contains("uk"))
        XCTAssertEqual(catalog.download(id: "parakeet-v3-ctc-vocab")?.optional, true)
        XCTAssertEqual(catalog.download(id: "whisper-large-v3-turbo")?.optional, false)
    }

    func testCatalogRejectsDownloadByteTotalMismatch() throws {
        var object = try manifestObject()
        var downloads = try XCTUnwrap(object["downloads"] as? [[String: Any]])
        downloads[0]["bytes"] = (downloads[0]["bytes"] as? Int ?? 0) + 1
        object["downloads"] = downloads

        XCTAssertThrowsError(try ModelCatalog(data: encoded(object)))
    }

    func testCatalogRejectsMutableModelRevision() throws {
        var object = try manifestObject()
        var downloads = try XCTUnwrap(object["downloads"] as? [[String: Any]])
        var files = try XCTUnwrap(downloads[0]["files"] as? [[String: Any]])
        files[0]["revision"] = "main"
        downloads[0]["files"] = files
        object["downloads"] = downloads

        XCTAssertThrowsError(try ModelCatalog(data: encoded(object)))
    }

    func testCatalogRejectsUnsafeDestinationPath() throws {
        var object = try manifestObject()
        var downloads = try XCTUnwrap(object["downloads"] as? [[String: Any]])
        var files = try XCTUnwrap(downloads[0]["files"] as? [[String: Any]])
        files[0]["destinationPath"] = "../../outside"
        downloads[0]["files"] = files
        object["downloads"] = downloads

        XCTAssertThrowsError(try ModelCatalog(data: encoded(object)))
    }

    func testCatalogRejectsMalformedChecksum() throws {
        var object = try manifestObject()
        var downloads = try XCTUnwrap(object["downloads"] as? [[String: Any]])
        var files = try XCTUnwrap(downloads[0]["files"] as? [[String: Any]])
        files[0]["sha256"] = "not-a-sha256"
        downloads[0]["files"] = files
        object["downloads"] = downloads

        XCTAssertThrowsError(try ModelCatalog(data: encoded(object)))
    }

    func testModelFileURLsArePublicHTTPSHuggingFaceLinks() throws {
        let catalog = try ModelCatalog(data: Data(contentsOf: manifestURL()))
        let file = try XCTUnwrap(catalog.download(id: "parakeet-v3")?.files.first)
        let url = try XCTUnwrap(file.sourceURL)

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
        XCTAssertTrue(url.path.contains(file.revision))
    }

    func testBundledCatalogLoadsForThePackagedApp() throws {
        let catalog = try ModelCatalog.bundled()

        XCTAssertEqual(catalog.engines.map(\.id), ["apple-speech", "parakeet-v3", "whisper-large-v3-turbo"])
    }
}
