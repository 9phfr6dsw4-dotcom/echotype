import AVFoundation
import Foundation
import Speech

public struct AppleSpeechTranscriber: Sendable {
    public enum TranscriptionError: LocalizedError, Equatable {
        case unavailable
        case unsupportedLocale(String)
        case emptyAudioFile

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Speech transcription is unavailable on this Mac."
            case .unsupportedLocale(let locale):
                return "Apple Speech does not support the locale \(locale)."
            case .emptyAudioFile:
                return "The recording is empty. Try speaking for a little longer."
            }
        }
    }

    public init() {}

    /// Checks support and installs system-managed speech assets after an explicit caller action.
    public func prepare(localeIdentifier: String) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw TranscriptionError.unsupportedLocale(localeIdentifier)
        }

        let modules: [any SpeechModule] = [
            SpeechTranscriber(locale: locale, preset: .progressiveTranscription),
            SpeechTranscriber(locale: locale, preset: .transcription)
        ]
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
        return locale.identifier
    }

    /// Transcribes a local audio file. This method does not request or download assets.
    public func transcribe(audioFileAt url: URL, localeIdentifier: String) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw TranscriptionError.unsupportedLocale(localeIdentifier)
        }

        let audioFile = try AVAudioFile(forReading: url)
        guard audioFile.length > 0 else {
            throw TranscriptionError.emptyAudioFile
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let resultsTask = Task.detached(priority: .userInitiated) {
            var transcript = LiveTranscriptText()
            for try await result in transcriber.results {
                transcript.consume(text: String(result.text.characters), isFinal: result.isFinal)
            }
            return transcript.finalizedText
        }

        do {
            guard let lastSample = try await analyzer.analyzeSequence(from: audioFile) else {
                await analyzer.cancelAndFinishNow()
                resultsTask.cancel()
                throw TranscriptionError.emptyAudioFile
            }
            try await analyzer.finalizeAndFinish(through: lastSample)
            return try await resultsTask.value
        } catch {
            await analyzer.cancelAndFinishNow()
            resultsTask.cancel()
            throw error
        }
    }
}
