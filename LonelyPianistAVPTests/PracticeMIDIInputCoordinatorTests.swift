import Foundation
@testable import LonelyPianistAVP
import Testing

@MainActor
private final class CapturingPracticeSessionEffectHandler: PracticeSessionEffectHandlerProtocol {
    private(set) var effects: [PracticeSessionEffect] = []

    func handle(effect: PracticeSessionEffect) {
        effects.append(effect)
    }
}

@Test
@MainActor
func refreshInNonGuidingStateStopsInput() {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let coordinator = PracticeMIDIInputCoordinator(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    coordinator.refresh(
        for: .init(
            practiceState: .ready,
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1)]
        )
    )

    #expect(source.stopCallCount == 0)
    #expect(source.isRunning == false)
}

@Test
@MainActor
func practiceMIDIInputCoordinator_shutdownIsIdempotent() {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let coordinator = PracticeMIDIInputCoordinator(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    coordinator.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1)]
        )
    )
    #expect(source.startCallCount == 1)
    #expect(source.isRunning == true)

    coordinator.shutdown()
    coordinator.shutdown()

    #expect(source.stopCallCount == 1)
}

@Test
@MainActor
func shutdownDoesNotCancelOtherConsumers() async {
    let source = FakeProtocolSeparatedPracticeInputEventSource()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()
    let coordinator = PracticeMIDIInputCoordinator(
        practiceInputEventSource: source,
        matcher: MIDIPracticeStepMatcher(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeEvents: true
    )

    coordinator.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            currentStepIndex: 0,
            expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1)]
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
            receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime,
            debugEventID: 1
        )
    )

    coordinator.shutdown()
    let received = await otherTask.value

    #expect(received == true)
}
