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
