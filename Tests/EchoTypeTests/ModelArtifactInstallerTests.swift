import Foundation
import XCTest
@testable import EchoTypeCore

final class ModelArtifactInstallerTests: XCTestCase {
    private let fixture = Data("EchoType installer fixture v1\n".utf8)
    private let fixtureSHA256 = "18b6c1b0168a1e55506e188373accf8f5d6b38156817350ad788bdae12288ac5"

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoTypeInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func modelFile(_ name: String, checksum: String? = nil) -> ModelFile {
        ModelFile(
            repo: "nvidia/parakeet-fixture",
            revision: String(repeating: "a", count: 40),
            sourcePath: name,
            destinationPath: "weights/\(name)",
            size: fixture.count,
            sha256: checksum ?? fixtureSHA256,
            sha256Source: "test-fixture"
        )
    }

    private func modelDownload(id: String = "fixture-model", files: [ModelFile]) -> ModelDownload {
        ModelDownload(
            id: id,
            engineId: "parakeet-v3",
            bytes: files.reduce(0) { $0 + $1.size },
            optional: false,
            license: "CC-BY-4.0",
            originalModel: nil,
            originalModelLicense: nil,
            files: files
        )
    }

    func testInstallerDoesNotFetchUntilExplicitlyAsked() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let counter = FetchCounter()
        let installer = ModelArtifactInstaller(modelsDirectory: root) { _, _ in
            counter.increment()
        }
        let download = modelDownload(files: [modelFile("weights.bin")])

        XCTAssertFalse(installer.isInstalled(download))
        XCTAssertEqual(counter.value, 0)
    }

    func testInstallerPublishesOnlyAfterEveryFilePassesChecksum() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureData = fixture
        let installer = ModelArtifactInstaller(modelsDirectory: root) { _, destination in
            try fixtureData.write(to: destination)
        }
        let download = modelDownload(files: [modelFile("weights.bin")])

        let installedURL = try await installer.install(download)

        XCTAssertEqual(try Data(contentsOf: installedURL.appendingPathComponent("weights/weights.bin")), fixtureData)
        XCTAssertTrue(installer.isInstalled(download))
    }

    func testChecksumMismatchLeavesNoInstalledOrPartialModel() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureSize = fixture.count
        let installer = ModelArtifactInstaller(modelsDirectory: root) { _, destination in
            try Data(repeating: 0, count: fixtureSize).write(to: destination)
        }
        let download = modelDownload(files: [modelFile("weights.bin")])

        do {
            _ = try await installer.install(download)
            XCTFail("A file with the wrong SHA-256 must not be installed")
        } catch let error as ModelArtifactInstallError {
            XCTAssertEqual(error, .checksumMismatch("weights/weights.bin"))
        }

        XCTAssertFalse(installer.isInstalled(download))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(download.id).path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testFailureOnLaterFileDoesNotPublishAnIncompleteModel() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureData = fixture
        let installer = ModelArtifactInstaller(modelsDirectory: root) { url, destination in
            if url.path.hasSuffix("second.bin") {
                throw URLError(.notConnectedToInternet)
            }
            try fixtureData.write(to: destination)
        }
        let download = modelDownload(files: [modelFile("first.bin"), modelFile("second.bin")])

        do {
            _ = try await installer.install(download)
            XCTFail("A failed file fetch must abort the whole model install")
        } catch is URLError {
            // Expected: installer must remove staging data and rethrow the transport error.
        }

        XCTAssertFalse(installer.isInstalled(download))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(download.id).path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInstalledModelCanBeRemovedAndRemovalIsIdempotent() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureData = fixture
        let installer = ModelArtifactInstaller(modelsDirectory: root) { _, destination in
            try fixtureData.write(to: destination)
        }
        let download = modelDownload(files: [modelFile("weights.bin")])
        let installedURL = try await installer.install(download)

        XCTAssertTrue(try installer.removeInstalled(download))
        XCTAssertFalse(installer.isInstalled(download))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedURL.path))
        XCTAssertFalse(try installer.removeInstalled(download))
    }

    func testRemovalRefusesAnUnverifiedDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let download = modelDownload(files: [modelFile("weights.bin")])
        let unverifiedURL = root.appendingPathComponent(download.id, isDirectory: true)
        try FileManager.default.createDirectory(at: unverifiedURL, withIntermediateDirectories: true)
        try Data("unverified".utf8).write(to: unverifiedURL.appendingPathComponent("keep.txt"))
        let installer = ModelArtifactInstaller(modelsDirectory: root) { _, _ in }

        XCTAssertThrowsError(try installer.removeInstalled(download))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unverifiedURL.appendingPathComponent("keep.txt").path))
    }
}

private final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
