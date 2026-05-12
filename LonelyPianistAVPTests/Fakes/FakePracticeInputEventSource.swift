import Foundation
@testable import LonelyPianistAVP

final class FakePracticeInputEventSource: PracticeInputEventSourceProtocol {
    var events: AsyncStream<PracticeInputEvent> {
        eventsStream
    }

    private let eventsStream: AsyncStream<PracticeInputEvent>
    private let eventsContinuation: AsyncStream<PracticeInputEvent>.Continuation

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isRunning = false

    init() {
        var continuation: AsyncStream<PracticeInputEvent>.Continuation?
        eventsStream = AsyncStream { continuation = $0 }
        eventsContinuation = continuation!
    }

    func start() throws {
        startCallCount += 1
        isRunning = true
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }

    func emit(_ event: PracticeInputEvent) {
        eventsContinuation.yield(event)
    }
}

