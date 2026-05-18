import Foundation
@testable import LonelyPianistAVP
import os

final class FakePracticeInputEventSource: PracticeInputEventSourceProtocol {
    private let broadcaster = PracticeInputEventBroadcaster()

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isRunning = false

    init() {}

    func eventsStream() -> AsyncStream<PracticeInputEvent> {
        broadcaster.makeStream()
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
        broadcaster.yield(event)
    }
}

private final class PracticeInputEventBroadcaster {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<PracticeInputEvent>.Continuation]())

    func makeStream() -> AsyncStream<PracticeInputEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations.withLock { state in
                state[id] = continuation
            }
            continuation.onTermination = { @Sendable _ in
                self.continuations.withLock { state in
                    state[id] = nil
                }
            }
        }
    }

    func yield(_ event: PracticeInputEvent) {
        let snapshot = continuations.withLock { state in
            Array(state.values)
        }
        for continuation in snapshot {
            continuation.yield(event)
        }
    }
}
