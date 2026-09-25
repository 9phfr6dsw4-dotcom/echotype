import AVFoundation
import EchoTypeCore
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechDictationViewModel {
    private(set) var isPreparingAssets = false
    private(set) var assetsPrepared = false
    private(set) var isRecording = false
    private(set) var isTranscribing = false
    private(set) var microphoneName = "System default microphone"
    private(set) var transcript = ""
    var errorMessage: String?

    @ObservationIgnored private let transcriber = AppleSpeechTranscriber()
    @ObservationIgnored private var preparedLocaleIdentifier: String?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var audioWriter: AudioFileWriter?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var inputBridge: AudioAnalyzerInputBridge?
    @ObservationIgnored private var speechAnalyzer: SpeechAnalyzer?
    @ObservationIgnored private var liveResultsTask: Task<Void, Never>?
    @ObservationIgnored private var liveTranscript = LiveTranscriptText()
    @ObservationIgnored var onChange: ((SpeechDictationViewModel) -> Void)?

    init() {
        Self.removeInterruptedRecordings()
    }

    func prepareAppleSpeech() async {
        guard !isPreparingAssets, !assetsPrepared else { return }
        isPreparingAssets = true
        errorMessage = nil
        defer { isPreparingAssets = false }

        do {
            preparedLocaleIdentifier = try await transcriber.prepare(localeIdentifier: Locale.current.identifier)
            assetsPrepared = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording() async {
        guard assetsPrepared, !isRecording, !isTranscribing else { return }
        errorMessage = nil

        guard await microphoneAccessGranted() else {
            errorMessage = "Microphone access is off. Allow EchoType in System Settings → Privacy & Security → Microphone."
            return
        }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            errorMessage = "No microphone is available. Connect or enable a microphone, then try again."
            return
        }
        guard let preparedLocaleIdentifier,
              let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: preparedLocaleIdentifier)
              ) else {
            errorMessage = "The prepared speech language is no longer available. Prepare Apple Speech again."
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            errorMessage = "The selected microphone is not ready. Check the audio input in System Settings."
            return
        }

        let liveTranscriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [liveTranscriber],
            considering: inputFormat
        ) else {
            errorMessage = "Apple Speech could not choose an audio format for this microphone."
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoTypeRecording-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let (inputSequence, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [liveTranscriber])
        let resultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in liveTranscriber.results {
                    guard let self else { return }
                    self.liveTranscript.consume(
                        text: String(result.text.characters),
                        isFinal: result.isFinal
                    )
                    self.transcript = self.liveTranscript.visibleText
                    self.onChange?(self)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
            }
        }

        var tapInstalled = false
        do {
            let writer = try AudioFileWriter(url: url, settings: inputFormat.settings)
            let converter = try SpeechAudioBufferConverter(inputFormat: inputFormat, outputFormat: analyzerFormat)
            let bridge = AudioAnalyzerInputBridge(converter: converter, continuation: continuation)

            try await analyzer.start(inputSequence: inputSequence)
            inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, _ in
                writer.write(buffer)
                bridge.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()

            audioEngine = engine
            audioWriter = writer
            recordingURL = url
            inputBridge = bridge
            speechAnalyzer = analyzer
            liveResultsTask = resultsTask
            microphoneName = device.localizedName
            transcript = ""
            liveTranscript.reset()
            isRecording = true
            onChange?(self)
        } catch {
            if tapInstalled {
                inputNode.removeTap(onBus: 0)
            }
            engine.stop()
            continuation.finish(throwing: error)
            await analyzer.cancelAndFinishNow()
            resultsTask.cancel()
            try? FileManager.default.removeItem(at: url)
            errorMessage = error.localizedDescription
        }
    }

    func stopAndTranscribe() async {
        guard isRecording, let engine = audioEngine, let recordingURL else { return }
        isRecording = false
        isTranscribing = true
        onChange?(self)
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
            self.isTranscribing = false
            self.onChange?(self)
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        let writeError = audioWriter?.errorMessage
        audioWriter = nil

        let bridge = inputBridge
        let bridgeError = bridge?.errorMessage
        bridge?.finish()
        inputBridge = nil
        if let bridgeError {
            errorMessage = "Live preview stopped early; the final local transcription will still run. \(bridgeError)"
        }
        let analyzer = speechAnalyzer
        speechAnalyzer = nil
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await liveResultsTask?.value
        liveResultsTask = nil

        let liveText = liveTranscript.visibleText
        if let writeError {
            transcript = liveText
            errorMessage = "Could not finish the temporary recording: \(writeError)"
            return
        }
        guard let preparedLocaleIdentifier else {
            transcript = liveText
            errorMessage = "Prepare Apple Speech before recording."
            return
        }

        do {
            let finalTranscript = try await transcriber.transcribe(
                audioFileAt: recordingURL,
                localeIdentifier: preparedLocaleIdentifier
            )
            transcript = finalTranscript.isEmpty ? liveText : finalTranscript
        } catch {
            transcript = liveText
            errorMessage = error.localizedDescription
        }
    }

    private func microphoneAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private static func removeInterruptedRecordings() {
        let directory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where file.lastPathComponent.hasPrefix("EchoTypeRecording-") && file.pathExtension == "caf" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private final class AudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let file: AVAudioFile
    private var writeFailure: String?

    var errorMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return writeFailure
    }

    init(url: URL, settings: [String: Any]) throws {
        file = try AVAudioFile(forWriting: url, settings: settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard writeFailure == nil else { return }
        do {
            try file.write(from: buffer)
        } catch {
            writeFailure = error.localizedDescription
        }
    }
}

private final class AudioAnalyzerInputBridge: @unchecked Sendable {
    // The audio tap calls append; stop halts the engine before finish. Lock order is bridge → converter → input source, with no reverse acquisition path.
    private let lock = NSLock()
    private let converter: SpeechAudioBufferConverter
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private var finished = false
    private var failureMessage: String?

    init(
        converter: SpeechAudioBufferConverter,
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    ) {
        self.converter = converter
        self.continuation = continuation
    }

    func append(_ input: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        do {
            let converted = try converter.convert(input)
            continuation.yield(AnalyzerInput(buffer: converted))
        } catch {
            finished = true
            failureMessage = error.localizedDescription
            continuation.finish(throwing: error)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.finish()
    }

    var errorMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return failureMessage
    }
}
