import AVFoundation
import EchoTypeCore
import Foundation
import Observation

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

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "The selected microphone is not ready. Check the audio input in System Settings."
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoTypeRecording-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        do {
            let writer = try AudioFileWriter(url: url, settings: format.settings)
            inputNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { buffer, _ in
                writer.write(buffer)
            }
            engine.prepare()
            try engine.start()

            audioEngine = engine
            audioWriter = writer
            recordingURL = url
            microphoneName = device.localizedName
            transcript = ""
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            try? FileManager.default.removeItem(at: url)
            errorMessage = error.localizedDescription
        }
    }

    func stopAndTranscribe() async {
        guard isRecording, let engine = audioEngine, let recordingURL else { return }
        isRecording = false
        isTranscribing = true
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
            self.isTranscribing = false
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        let writeError = audioWriter?.errorMessage
        audioWriter = nil

        if let writeError {
            errorMessage = "Could not save the temporary recording: \(writeError)"
            return
        }

        guard let preparedLocaleIdentifier else {
            errorMessage = "Prepare Apple Speech before recording."
            return
        }

        do {
            transcript = try await transcriber.transcribe(
                audioFileAt: recordingURL,
                localeIdentifier: preparedLocaleIdentifier
            )
        } catch {
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
