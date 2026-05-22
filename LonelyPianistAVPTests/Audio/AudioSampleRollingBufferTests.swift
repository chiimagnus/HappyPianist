@testable import LonelyPianistAVP
import Testing

struct AudioSampleRollingBufferTests {
    @Test func rollingBufferKeepsLatestWindow() {
        var buffer = AudioSampleRollingBuffer(capacity: 4)
        buffer.append([1, 2, 3])
        buffer.append([4, 5])
        #expect(buffer.count == 4)
        #expect(buffer.window(size: 3) == [3, 4, 5])
        buffer.reset()
        #expect(buffer.window(size: 1) == nil)
    }
}

extension AudioSampleRollingBufferTests {
    @Test func lowRegisterWindowRequiresEnoughSamplesAndUsesLatest4096() {
        var buffer = AudioSampleRollingBuffer(capacity: 4096)
        buffer.append(Array(repeating: Float(1), count: 2048))
        #expect(buffer.window(size: 4096) == nil)

        buffer.append(Array(repeating: Float(2), count: 4096))
        let window = buffer.window(size: 4096)
        #expect(window?.count == 4096)
        #expect(window?.first == 2)
        #expect(window?.last == 2)
    }

    @Test func resetClearsPotentialCrossGenerationSamples() {
        var buffer = AudioSampleRollingBuffer(capacity: 4096)
        buffer.append(Array(repeating: Float(1), count: 4096))
        #expect(buffer.window(size: 4096) != nil)

        buffer.reset()

        #expect(buffer.window(size: 1) == nil)
        #expect(buffer.count == 0)
    }
}
