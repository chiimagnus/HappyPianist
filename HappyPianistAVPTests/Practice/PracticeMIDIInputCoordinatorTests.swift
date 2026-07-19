import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class CapturingPracticeSessionEffectHandler: PracticeSessionEffectHandlerProtocol {
    private(set) var effects: [PracticeSessionEffect] = []

    func handle(effect: PracticeSessionEffect) {
        effects.append(effect)
    }
}

@MainActor
private final class CapturingMIDIPracticeStepMatcher: MIDIPracticeStepMatchingProtocol {
    struct ResetCall {
        let stepIndex: Int
        let expectedNotes: [PracticeStepNote]
    }

    private(set) var resetCalls: [ResetCall] = []

    func reset(stepIndex: Int, expectedNotes: [PracticeStepNote], configuredAt _: Date) {
        resetCalls.append(ResetCall(stepIndex: stepIndex, expectedNotes: expectedNotes))
    }

    func registerNoteOn(note _: Int, at _: Date) -> StepAttemptMatchResult {
        .insufficientEvidence
    }

    func registerNoteOff(note _: Int, at _: Date) {}
}

@Test
@MainActor
func refreshInNonGuidingStateStopsInput() {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let service = PracticeMIDIInputService(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    service.refresh(
        for: .init(
            practiceState: .ready,
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]
        )
    )

    #expect(source.stopCallCount == 0)
    #expect(source.isRunning == false)
}

@Test
@MainActor
func practiceMIDIInputService_shutdownIsIdempotent() {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let service = PracticeMIDIInputService(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    service.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]
        )
    )
    #expect(source.startCallCount == 1)
    #expect(source.isRunning == true)

    service.shutdown()
    service.shutdown()

    #expect(source.stopCallCount == 1)
}

@Test
@MainActor
func shutdownDoesNotCancelOtherConsumers() async {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let service = PracticeMIDIInputService(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    service.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]
        )
    )

    let otherStream = source.midi1EventsStream()
    let otherTask = Task {
        for await _ in otherStream {
            return true
        }
        return false
    }

    source.emitMIDI1(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 1),
            channel: 1,
            group: 0,
            source: .init(identifier: .sourceIndex(0), endpointName: "test"),
            receivedAt: .now,
            receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    )

    service.shutdown()
    let received = await otherTask.value

    #expect(received == true)
}

@Test
@MainActor
func allNotesOffResetsActiveMatcherWithoutStoppingInput() async {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let matcher = CapturingMIDIPracticeStepMatcher()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let expectedNotes = [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]
    let service = PracticeMIDIInputService(
        practiceInputEventSource: source,
        matcher: matcher,
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    service.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: expectedNotes
        )
    )
    #expect(matcher.resetCalls.count == 1)

    source.emitMIDI1(
        MIDI1InputEvent(
            kind: .controlChange(controller: 123, value: 0),
            channel: 1,
            group: 0,
            source: .init(identifier: .sourceIndex(0), endpointName: "test"),
            receivedAt: .now,
            receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    )

    for _ in 0 ..< 100 where matcher.resetCalls.count < 2 {
        await Task.yield()
    }

    #expect(matcher.resetCalls.count == 2)
    #expect(matcher.resetCalls.last?.stepIndex == 0)
    #expect(matcher.resetCalls.last?.expectedNotes == expectedNotes)
    #expect(source.isRunning)
}

@Test
func midiObservationAdapterPreservesMIDI1EvidenceAndRouting() {
    var adapter = MIDIPerformanceObservationAdapter()
    let observation = adapter.observation(
        for: MIDI1InputEvent(
            kind: .controlChange(controller: 64, value: 96),
            channel: 12,
            group: 3,
            source: .init(identifier: .endpointUniqueID(42), endpointName: "Private device name"),
            receivedAt: .now,
            receivedAtUptimeSeconds: 20,
            sourceTimestamp: PerformanceSourceTimestamp(clockID: "host", seconds: 19.5)
        ),
        generation: 7
    )

    #expect(observation.source.id == "endpoint:42")
    #expect(observation.source.generation == 7)
    #expect(observation.channel == 12)
    #expect(observation.group == 3)
    #expect(observation.timing.source?.seconds == 19.5)
    guard case let .controller(.controlChange(number, value)) = observation.event else {
        Issue.record("Expected control change")
        return
    }
    #expect(number == 64)
    #expect(value == PerformanceObservation.NormalizedValue(midi1: 96))
}

@Test
func midiObservationAdapterKeepsMIDI2PrecisionUntilOutputBoundary() {
    var adapter = MIDIPerformanceObservationAdapter()
    let observation = adapter.observation(
        for: MIDI2InputEvent(
            kind: .controlChange(controller: 67, value32: 0x1234_5678),
            channel: 1,
            group: 15,
            source: .init(identifier: .sourceIndex(2), endpointName: nil),
            receivedAt: .now,
            receivedAtUptimeSeconds: 1
        ),
        generation: 1
    )

    guard case let .controller(.controlChange(number, value)) = observation.event else {
        Issue.record("Expected control change")
        return
    }
    #expect(number == 67)
    #expect(value.rawValue == 0x1234_5678)
}

@Test
@MainActor
func practiceMIDIInputPublishesOnlyCurrentGenerationObservations() async throws {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let service = PracticeMIDIInputService(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: CapturingPracticeSessionEffectHandler(),
        consumeEvents: true
    )
    let stream = service.performanceObservationsStream()
    service.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]
        )
    )
    let generation = stateStore.practiceInputGeneration
    let task = Task<PerformanceObservation?, Never> { @MainActor in
        for await observation in stream {
            return observation
        }
        return nil
    }

    source.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 87),
        channel: 2,
        group: 1,
        source: .init(identifier: .sourceIndex(0), endpointName: nil),
        receivedAt: .now,
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    let observation = try #require(await task.value)
    #expect(observation.source.generation == UInt64(generation))
    #expect(observation.channel == 2)
    guard case let .noteOn(note, velocity) = observation.event else {
        Issue.record("Expected note-on observation")
        return
    }
    #expect(note == 60)
    #expect(velocity == PerformanceObservation.NormalizedValue(midi1: 87))
}
