import Foundation
import MIDI
import MusicXML
import Practice
import Testing

@Test
@MainActor
func midiSessionRejectsStaleEventsAfterConfigurationGenerationChanges() async {
    let source = TestMIDIInputEventSource()
    let matcher = RecordingMIDIPracticeMatcher()
    let session = MIDIPracticeSession(inputEventSource: source, matcher: matcher)

    session.update(configuration: configuration(stepIndex: 0, note: 60))
    #expect(source.startCount == 1)
    #expect(matcher.resets == [0])

    session.update(configuration: configuration(stepIndex: 1, note: 62))
    source.send(noteOn: 60, uptimeSeconds: 0)
    #expect(await settles { matcher.observations.isEmpty })
    source.send(noteOn: 62, uptimeSeconds: ProcessInfo.processInfo.systemUptime + 1)

    #expect(await settles { matcher.observations.count == 1 })
    #expect(matcher.resets == [0, 1])
    #expect(matcher.observedMIDINotes == [62])

    session.shutdown()
}

@Test
@MainActor
func midiSessionResetsMatcherWhenExpectedNotesChangeWithinTheSameStep() {
    let source = TestMIDIInputEventSource()
    let matcher = RecordingMIDIPracticeMatcher()
    let session = MIDIPracticeSession(inputEventSource: source, matcher: matcher)

    session.update(configuration: configuration(stepIndex: 0, note: 60))
    session.update(configuration: configuration(stepIndex: 0, note: 62))

    #expect(source.startCount == 1)
    #expect(matcher.resetNotes == [[60], [62]])

    session.shutdown()
}

@Test
@MainActor
func midiSessionResetsOnDiscontinuityAndFinishesOnShutdown() async {
    let source = TestMIDIInputEventSource()
    let matcher = RecordingMIDIPracticeMatcher()
    let session = MIDIPracticeSession(inputEventSource: source, matcher: matcher)

    session.update(configuration: configuration(stepIndex: 0, note: 60))
    #expect(source.startCount == 1)

    source.send(
        kind: .controlChange(controller: 120, value: 0),
        uptimeSeconds: ProcessInfo.processInfo.systemUptime + 1
    )
    #expect(await settles { matcher.resets == [0, 0] })

    session.stop()
    #expect(source.stopCount == 1)
    #expect(matcher.resets.last == -1)

    source.send(noteOn: 60, uptimeSeconds: ProcessInfo.processInfo.systemUptime + 1)
    #expect(await settles { matcher.observations.isEmpty })

    session.shutdown()
}

@Test
@MainActor
func midiSessionFinishesInInputOutputRecordingProgressOrder() async {
    let source = TestMIDIInputEventSource()
    let session = MIDIPracticeSession(inputEventSource: source)
    let probe = TerminationProbe()

    session.update(configuration: configuration(stepIndex: 0, note: 60))
    let didFinish = await session.finish(termination: .init(
        resetOutput: {
            probe.inputWasStoppedBeforeOutput = source.stopCount == 1
            probe.events.append("output")
        },
        flushProgress: {
            probe.events.append("progress")
            return true
        }
    ))

    #expect(didFinish)
    #expect(probe.inputWasStoppedBeforeOutput)
    #expect(probe.events == ["output", "progress"])
    #expect(source.stopCount == 1)
}

@Test
@MainActor
func midiSessionKeepsLifecycleResumableWhenProgressFlushFails() async {
    let source = TestMIDIInputEventSource()
    let session = MIDIPracticeSession(inputEventSource: source)

    session.update(configuration: configuration(stepIndex: 0, note: 60))
    let didFinish = await session.finish(termination: .init(
        resetOutput: {},
        flushProgress: { false }
    ))

    #expect(didFinish == false)
    #expect(source.stopCount == 1)

    session.update(configuration: configuration(stepIndex: 0, note: 60))
    #expect(source.startCount == 2)
    session.shutdown()
}

@MainActor
private func configuration(stepIndex: Int, note: Int) -> MIDIPracticeSession.Configuration {
    MIDIPracticeSession.Configuration(
        acceptsInput: true,
        currentStepIndex: stepIndex,
        expectedNotes: [PracticeStepNote(
            midiNote: note,
            staff: 1,
            handAssignment: ScoreHandAssignment(
                hand: .right,
                provenance: .score,
                confidence: nil
            )
        )]
    )
}

@MainActor
private func settles(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 100 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

@MainActor
private final class TerminationProbe {
    var inputWasStoppedBeforeOutput = false
    var events: [String] = []
}

@MainActor
private final class RecordingMIDIPracticeMatcher: MIDIPracticeStepMatchingProtocol {
    private(set) var resets: [Int] = []
    private(set) var resetNotes: [[Int]] = []
    private(set) var observations: [PerformanceObservation] = []

    var observedMIDINotes: [Int] {
        observations.compactMap { observation in
            guard case let .noteOn(note, _) = observation.event else { return nil }
            return note
        }
    }

    func reset(stepIndex: Int, expectedNotes: [PracticeStepNote]) {
        resets.append(stepIndex)
        resetNotes.append(expectedNotes.map(\.midiNote))
    }

    func register(_ observation: PerformanceObservation) -> StepAttemptMatchResult? {
        observations.append(observation)
        if case .noteOn = observation.event { return .matched }
        return nil
    }
}

private final class TestMIDIInputEventSource: MIDIInputEventSource {
    private let midi1Stream: AsyncStream<MIDI1InputEvent>
    private let midi1Continuation: AsyncStream<MIDI1InputEvent>.Continuation
    private let midi2Stream: AsyncStream<MIDI2InputEvent>
    private let midi2Continuation: AsyncStream<MIDI2InputEvent>.Continuation

    private(set) var startCount = 0
    private(set) var stopCount = 0

    init() {
        let midi1 = Self.makeStream(MIDI1InputEvent.self)
        midi1Stream = midi1.stream
        midi1Continuation = midi1.continuation
        let midi2 = Self.makeStream(MIDI2InputEvent.self)
        midi2Stream = midi2.stream
        midi2Continuation = midi2.continuation
    }

    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        midi1Stream
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        midi2Stream
    }

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func send(noteOn note: Int, uptimeSeconds: TimeInterval) {
        send(kind: .noteOn(note: note, velocity: 100), uptimeSeconds: uptimeSeconds)
    }

    func send(kind: MIDI1InputEvent.Kind, uptimeSeconds: TimeInterval) {
        midi1Continuation.yield(MIDI1InputEvent(
            kind: kind,
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .endpointUniqueID(1), endpointName: "Test MIDI"),
            receivedAt: .now,
            receivedAtUptimeSeconds: uptimeSeconds
        ))
    }

    deinit {
        midi1Continuation.finish()
        midi2Continuation.finish()
    }

    private static func makeStream<Event>(
        _: Event.Type
    ) -> (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation) {
        var capturedContinuation: AsyncStream<Event>.Continuation?
        let stream = AsyncStream<Event> { continuation in
            capturedContinuation = continuation
        }
        guard let capturedContinuation else {
            fatalError("AsyncStream continuation was not created")
        }
        return (stream, capturedContinuation)
    }
}
