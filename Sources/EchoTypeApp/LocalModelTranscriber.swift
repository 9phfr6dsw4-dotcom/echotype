import EchoTypeCore
import FluidAudio
import Foundation
import WhisperKit

struct LocalModelTranscriber {
    enum TranscriptionError: LocalizedError {
        case unavailableBackend(String)
        case missingLocalAsset(String)
        case unsupportedParakeetLanguage(String)
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .unavailableBackend(let engineID):
                return "The selected transcription engine is not installed or supported: \(engineID)."
            case .missingLocalAsset(let path):
                return "A required local model file is missing: \(path). Reinstall the model from EchoType."
            case .unsupportedParakeetLanguage(let language):
                return "Parakeet v3 does not support the selected language (\(language)). Choose one of its 25 listed languages or use Whisper/Apple Speech."
            case .emptyTranscript:
                return "No speech was recognized. Try again or check the microphone input."
            }
        }
    }

    static func transcribe(
        backend: TranscriptionBackend,
        audioURL: URL,
        modelDirectory: URL,
        languageIdentifier: String?
    ) async throws -> String {
        switch backend {
        case .parakeetV3:
            return try await transcribeParakeet(
                audioURL: audioURL,
                modelDirectory: modelDirectory,
                languageIdentifier: languageIdentifier
            )
        case .whisperLargeV3Turbo:
            return try await transcribeWhisper(
                audioURL: audioURL,
                modelDirectory: modelDirectory,
                languageIdentifier: languageIdentifier
            )
        case .appleSpeech, .unavailable:
            throw TranscriptionError.unavailableBackend(String(describing: backend))
        }
    }

    private static func transcribeParakeet(
        audioURL: URL,
        modelDirectory: URL,
        languageIdentifier: String?
    ) async throws -> String {
        let code = normalizedLanguageCode(languageIdentifier)
        let language: Language?
        if let code {
            guard let supported = Language(rawValue: code) else {
                throw TranscriptionError.unsupportedParakeetLanguage(languageIdentifier ?? code)
            }
            language = supported
        } else {
            language = nil
        }

        let models = try AsrModels.loadLocal(from: modelDirectory, version: .v3)
        let manager = AsrManager(config: .default, models: models)
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: language
        )
        return try nonempty(result.text)
    }

    private static func transcribeWhisper(
        audioURL: URL,
        modelDirectory: URL,
        languageIdentifier: String?
    ) async throws -> String {
        let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")
        guard FileManager.default.fileExists(atPath: tokenizerURL.path) else {
            throw TranscriptionError.missingLocalAsset(tokenizerURL.lastPathComponent)
        }
        let offlineHub = HubApiWrapper(
            downloadBase: modelDirectory,
            endpoint: "file:///EchoType-offline-hub"
        )
        let localTokenizer = try await AutoTokenizerWrapper.from(
            modelFolder: modelDirectory,
            hubApi: offlineHub
        )
        guard localTokenizer.convertTokenToId("<|endoftext|>") != nil else {
            throw TranscriptionError.missingLocalAsset("tokenizer.json (Whisper special tokens)")
        }

        let config = WhisperKitConfig(
            modelFolder: modelDirectory.path,
            tokenizerFolder: modelDirectory,
            verbose: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        let whisper = try await WhisperKit(config)
        let options = DecodingOptions(
            language: normalizedLanguageCode(languageIdentifier),
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return try nonempty(results.map(\.text).joined(separator: " "))
    }

    private static func normalizedLanguageCode(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let firstPart = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return firstPart.map(String.init)?.lowercased()
    }

    private static func nonempty(_ text: String) throws -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TranscriptionError.emptyTranscript }
        return cleaned
    }
}
