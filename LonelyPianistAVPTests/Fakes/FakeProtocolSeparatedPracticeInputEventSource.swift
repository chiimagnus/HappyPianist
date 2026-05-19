import Foundation
@testable import LonelyPianistAVP

final class FakeProtocolSeparatedPracticeInputEventSource: PracticeInputEventSourceProtocol {
    enum StartError: Error {
        case simulatedFailure
    }

    private let midi1Broadcaster = AsyncStreamBroadcaster<MIDI1InputEvent>()
    private let midi2Broadcaster = AsyncStreamBroadcaster<MIDI2InputEvent>()

    private(set) var midi1StreamCallCount = 0
    private(set) var midi2StreamCallCount = 0

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isRunning = false
    private(set) var eventsAfterStopCount = 0
    var shouldFailNextStart = false

    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        midi1StreamCallCount += 1
        return midi1Broadcaster.makeStream()
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        midi2StreamCallCount += 1
        return midi2Broadcaster.makeStream()
    }

    func start() throws {
        startCallCount += 1
        if shouldFailNextStart {
            shouldFailNextStart = false
            isRunning = false
            throw StartError.simulatedFailure
        }
        isRunning = true
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }

    func emitMIDI1(_ event: MIDI1InputEvent) {
        if !isRunning {
            eventsAfterStopCount += 1
        }
        midi1Broadcaster.yield(event)
    }

    func emitMIDI2(_ event: MIDI2InputEvent) {
        if !isRunning {
            eventsAfterStopCount += 1
        }
        midi2Broadcaster.yield(event)
    }
}
