import Foundation
@testable import LonelyPianistAVP

final class FakeBluetoothMIDIPracticeInputService: BluetoothMIDIPracticeInputServiceProtocol {
    struct StartCall: Equatable {
        let generation: Int
    }

    private(set) var startCalls: [StartCall] = []
    private(set) var updateGenerations: [Int] = []
    private(set) var stopCallCount = 0

    var startReturnSourceCount = 1

    var events: AsyncStream<DetectedNoteEvent> {
        eventsStream
    }

    private let eventsStream: AsyncStream<DetectedNoteEvent>
    private let eventsContinuation: AsyncStream<DetectedNoteEvent>.Continuation

    init() {
        var continuation: AsyncStream<DetectedNoteEvent>.Continuation?
        eventsStream = AsyncStream { continuation = $0 }
        eventsContinuation = continuation!
    }

    func start(generation: Int) throws -> Int {
        startCalls.append(.init(generation: generation))
        return startReturnSourceCount
    }

    func updateGeneration(_ generation: Int) {
        updateGenerations.append(generation)
    }

    func stop() {
        stopCallCount += 1
    }

    func emitEvent(_ event: DetectedNoteEvent) {
        eventsContinuation.yield(event)
    }
}

