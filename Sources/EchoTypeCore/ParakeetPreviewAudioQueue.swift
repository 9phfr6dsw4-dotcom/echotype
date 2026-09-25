import AVFoundation
import Foundation

/// Copies tap-owned PCM into a bounded, single-consumer stream. No transcription,
/// format conversion, main-actor work, or UI callbacks occur on the audio thread.
public final class ParakeetPreviewAudioQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    public let buffers: AsyncStream<AVAudioPCMBuffer>
    private let maximumFrames: Double
    private var receivedFrames: Double = 0
    private var active = true

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    /// A hard lifetime cap also bounds FluidAudio's internal unbounded input stream.
    /// A full recording always continues to the CAF/batch path after preview expires.
    public init(sampleRate: Double, maximumSeconds: Double = 45) {
        maximumFrames = sampleRate * maximumSeconds
        let (stream, builder) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingOldest(512)
        )
        buffers = stream
        continuation = builder
    }

    public func append(_ input: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard active, input.frameLength > 0 else { return }
        let frames = Double(input.frameLength)
        guard receivedFrames + frames <= maximumFrames,
              let copy = Self.copy(input) else {
            stopLocked()
            return
        }
        receivedFrames += frames
        switch continuation.yield(copy) {
        case .enqueued: break
        case .dropped, .terminated: stopLocked() // Never transcribe audio with a gap.
        @unknown default: stopLocked()
        }
    }

    public func finish() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        guard active else { return }
        active = false
        continuation.finish()
    }

    private static func copy(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
            return nil
        }
        output.frameLength = input.frameLength
        let sources = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        let destinations = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        guard sources.count == destinations.count else { return nil }
        for index in sources.indices {
            guard let source = sources[index].mData, let destination = destinations[index].mData,
                  destinations[index].mDataByteSize >= sources[index].mDataByteSize else { return nil }
            destination.copyMemory(from: source, byteCount: Int(sources[index].mDataByteSize))
        }
        return output
    }
}
