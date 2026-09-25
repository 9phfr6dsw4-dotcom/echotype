@preconcurrency import AVFoundation
import EchoTypeCore
import FluidAudio
import Foundation

/// Optional, best-effort display path. Never supplies the delivered transcript.
enum ParakeetLivePreview {
    static func run(
        audio: ParakeetPreviewAudioQueue,
        modelDirectory: URL,
        languageIdentifier: String,
        onUpdate: @escaping @Sendable (String) -> Void
    ) async {
        guard !Task.isCancelled else { return }
        let code = languageIdentifier.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init)?.lowercased()
        let config = SlidingWindowAsrConfig(
            chunkSeconds: 2,
            hypothesisChunkSeconds: 1,
            leftContextSeconds: 1,
            rightContextSeconds: 0.5,
            minContextForConfirmation: 8,
            confirmationThreshold: 0.85,
            language: code.flatMap(Language.init(rawValue:))
        )
        let manager = SlidingWindowAsrManager(config: config)
        do {
            // Never call loadModels(to:) here: it downloads. Use exactly the batch model assets.
            let models = try AsrModels.loadLocal(
                from: modelDirectory, version: .v3, encoderPrecision: .int8V2
            )
            guard !Task.isCancelled else { return }
            try await manager.loadModels(models)
            guard !Task.isCancelled else {
                await manager.cleanup()
                return
            }
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                channels: 1, interleaved: false
            ) else {
                await manager.cleanup()
                return
            }
            try await manager.startStreaming()
            let updates = Task {
                for await _ in await manager.transcriptionUpdates {
                    guard !Task.isCancelled else { break }
                    let confirmed = await manager.confirmedTranscript
                    let volatile = await manager.volatileTranscript
                    let text = [confirmed, volatile].filter { !$0.isEmpty }.joined(separator: " ")
                    if !text.isEmpty { onUpdate(text) }
                }
            }
            do {
                var converter: SpeechAudioBufferConverter?
                for await captured in audio.buffers {
                    try Task.checkCancellation()
                    let buffer = captured.buffer
                    // The tap only copies. Conversion and actor hops run on this worker.
                    let activeConverter: SpeechAudioBufferConverter
                    if let converter {
                        activeConverter = converter
                    } else {
                        let created = try SpeechAudioBufferConverter(
                            inputFormat: buffer.format, outputFormat: format
                        )
                        converter = created
                        activeConverter = created
                    }
                    let converted = try activeConverter.convert(buffer)
                    await manager.streamAudio(converted)
                }
                if !Task.isCancelled { _ = try await manager.finish() }
            } catch {
                // Preview failure is invisible; the CAF and full-file batch stay authoritative.
            }
            await manager.cleanup()
            updates.cancel()
        } catch {
            await manager.cleanup()
        }
    }
}
