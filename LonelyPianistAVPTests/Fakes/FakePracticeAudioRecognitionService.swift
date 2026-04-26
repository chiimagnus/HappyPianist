import Foundation
@testable import LonelyPianistAVP

final class FakePracticeAudioRecognitionService: PracticeAudioRecognitionServiceProtocol {
    struct StartCall: Equatable {
        let expectedMIDINotes: [Int]
        let wrongCandidateMIDINotes: [Int]
        let generation: Int
        let suppressUntil: Date?
    }

    struct UpdateCall: Equatable {
        let expectedMIDINotes: [Int]
        let wrongCandidateMIDINotes: [Int]
        let generation: Int
    }

    struct SuppressCall: Equatable {
        let until: Date
        let generation: Int
    }

    var events: AsyncStream<DetectedNoteEvent> {
        eventsStream
    }

    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> {
        statusStream
    }

    var debugSnapshots: AsyncStream<PracticeAudioRecognitionDebugSnapshot> {
        debugStream
    }

    private let eventsStream: AsyncStream<DetectedNoteEvent>
    private let statusStream: AsyncStream<PracticeAudioRecognitionStatus>
    private let debugStream: AsyncStream<PracticeAudioRecognitionDebugSnapshot>

    private let eventsContinuation: AsyncStream<DetectedNoteEvent>.Continuation
    private let statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation
    private let debugContinuation: AsyncStream<PracticeAudioRecognitionDebugSnapshot>.Continuation

    private(set) var startCalls: [StartCall] = []
    private(set) var updateCalls: [UpdateCall] = []
    private(set) var suppressCalls: [SuppressCall] = []
    private(set) var stopCallCount = 0
    private var currentGeneration = 0

    init() {
        var eventsContinuation: AsyncStream<DetectedNoteEvent>.Continuation?
        eventsStream = AsyncStream { continuation in
            eventsContinuation = continuation
        }

        var statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation?
        statusStream = AsyncStream { continuation in
            statusContinuation = continuation
        }

        var debugContinuation: AsyncStream<PracticeAudioRecognitionDebugSnapshot>.Continuation?
        debugStream = AsyncStream { continuation in
            debugContinuation = continuation
        }

        self.eventsContinuation = eventsContinuation!
        self.statusContinuation = statusContinuation!
        self.debugContinuation = debugContinuation!
    }

    func start(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressUntil: Date?
    ) async throws {
        currentGeneration = generation
        startCalls.append(
            StartCall(
                expectedMIDINotes: expectedMIDINotes,
                wrongCandidateMIDINotes: wrongCandidateMIDINotes,
                generation: generation,
                suppressUntil: suppressUntil
            )
        )
    }

    func updateExpectedNotes(_ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int) {
        currentGeneration = generation
        updateCalls.append(
            UpdateCall(
                expectedMIDINotes: expectedMIDINotes,
                wrongCandidateMIDINotes: wrongCandidateMIDINotes,
                generation: generation
            )
        )
    }

    func suppressRecognition(until date: Date, generation: Int) {
        guard generation == currentGeneration else { return }
        suppressCalls.append(SuppressCall(until: date, generation: generation))
    }

    func stop() {
        stopCallCount += 1
    }

    func emitEvent(_ event: DetectedNoteEvent) {
        eventsContinuation.yield(event)
    }

    func emitStatus(_ status: PracticeAudioRecognitionStatus) {
        statusContinuation.yield(status)
    }

    func emitDebugSnapshot(_ snapshot: PracticeAudioRecognitionDebugSnapshot) {
        debugContinuation.yield(snapshot)
    }
}
