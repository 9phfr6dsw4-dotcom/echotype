import AVFoundation
import XCTest
@testable import EchoTypeCore

final class ParakeetPreviewAudioQueueTests: XCTestCase {
    func testTapCopiesAudioBeforeTheSourceBufferIsReusedAndConvertsOffTap() async throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000, channels: 2, interleaved: false))
        let outputFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000, channels: 1, interleaved: false))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_800))
        source.frameLength = 4_800
        for channel in 0..<2 {
            source.floatChannelData![channel].update(repeating: 0.25, count: 4_800)
        }
        let queue = ParakeetPreviewAudioQueue(sampleRate: 48_000)
        let tap = AudioTapHandlerFactory.make { buffer in queue.append(buffer) }
        tap(source, AVAudioTime(sampleTime: 0, atRate: 48_000))
        source.floatChannelData![0].update(repeating: 0, count: 4_800)
        source.floatChannelData![1].update(repeating: 0, count: 4_800)
        queue.finish()
        var iterator = queue.buffers.makeAsyncIterator()
        let nextBuffer = await iterator.next()
        let captured = try XCTUnwrap(nextBuffer).buffer
        XCTAssertEqual(captured.floatChannelData![0][0], 0.25)
        let converter = try SpeechAudioBufferConverter(inputFormat: inputFormat, outputFormat: outputFormat)
        let converted = try converter.convert(captured)
        XCTAssertEqual(converted.format.sampleRate, 16_000)
        XCTAssertEqual(converted.format.channelCount, 1)
        XCTAssertGreaterThan(converted.frameLength, 0)
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testAudioCapStopsPreviewAtBound() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        let queue = ParakeetPreviewAudioQueue(sampleRate: 16_000, maximumSeconds: 1)
        queue.append(buffer)
        queue.append(buffer)
        queue.append(buffer)
        XCTAssertFalse(queue.isActive)
    }
}
