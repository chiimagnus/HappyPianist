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
private final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var stopCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0
    private(set) var loadedSequence: PracticeSequencerSequence?

    var currentSecondsValue: TimeInterval = 0

    func warmUp() throws {}

    func stop() {
        stopCallCount += 1
    }

    func load(sequence: PracticeSequencerSequence) throws {
        loadCallCount += 1
        loadedSequence = sequence
    }

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
    }

    func currentSeconds() -> TimeInterval {
        currentSecondsValue
    }

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private struct YieldingSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        await Task.yield()
    }
}

@Test
@MainActor
func manualReplayProjectsCanonicalPlanAndRestoresRecognitionAfterCompletion() async throws {
    let sequencer = FakeSequencerPlaybackService()
    sequencer.currentSecondsValue = 999

    let stateStore = PracticeSessionStateStore()
    stateStore.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
        PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 67, staff: 1, handAssignment: .unknown)]),
    ]
    stateStore.performancePlan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 55, velocity: 70, onTick: 0, offTick: 720),
        TestScorePerformanceNote(midiNote: 62, velocity: 31, onTick: 480, offTick: 600),
        TestScorePerformanceNote(midiNote: 65, velocity: 99, onTick: 540, offTick: 720),
    ], tempoEvents: [
        ScorePerformanceTempoEvent(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 120,
            endTick: nil,
            endQuarterBPM: nil
        ),
    ], controllerEvents: [
        ScorePerformanceControllerEvent(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 240,
            controllerNumber: 64,
            value: 48,
            outputCapabilityRequirement: .continuousControlChange
        ),
        ScorePerformanceControllerEvent(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 600,
            controllerNumber: 64,
            value: 100,
            outputCapabilityRequirement: .continuousControlChange
        ),
    ], annotations: [
        ScorePerformanceAnnotation(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 720,
            durationTicks: 240,
            kind: .pause,
            text: "fermata",
            provenance: []
        ),
    ])
    stateStore.currentStepIndex = 1
    stateStore.isAudioRecognitionRunning = true

    stateStore.highlightGuides = [
        PianoHighlightGuide(
            id: 0,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 480,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let effectHandler = CapturingPracticeSessionEffectHandler()
    let service = PracticeManualReplayService(
        sleeper: YieldingSleeper(),
        sequencerPlaybackService: sequencer,
        playbackSequenceBuilder: PlaybackSequenceBuilder(),
        stateStore: stateStore,
        effectHandler: effectHandler
    )

    service.startManualReplay(with: ManualReplayPlan(stepRange: 1 ..< 2))
    for _ in 0 ..< 20 {
        await Task.yield()
    }

    #expect(effectHandler.effects.contains(.stopAudioRecognition))
    #expect(effectHandler.effects.contains(.refreshAudioRecognition))
    #expect(stateStore.isManualReplayPlaying == false)
    #expect(stateStore.currentStepIndex == 1)
    #expect(sequencer.loadCallCount == 1)
    #expect(sequencer.playCallCount == 1)

    let events = try #require(sequencer.loadedSequence?.events)
    #expect(events.map(\.kind) == [
        .controlChange(controller: 64, value: 48),
        .noteOn(midi: 55, velocity: 70),
        .noteOn(midi: 62, velocity: 31),
        .noteOn(midi: 65, velocity: 99),
        .noteOff(midi: 62),
        .controlChange(controller: 64, value: 100),
        .noteOff(midi: 55),
        .noteOff(midi: 65),
    ])
    #expect(events.map(\.timeSeconds) == [0.05, 0.05, 0.05, 0.1125, 0.175, 0.175, 0.55, 0.55])
}

@Test
@MainActor
func practiceManualReplayService_shutdownIsIdempotent() async {
    let sequencer = FakeSequencerPlaybackService()
    sequencer.currentSecondsValue = 0

    let stateStore = PracticeSessionStateStore()
    stateStore.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
    ]
    stateStore.performancePlan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, offTick: 960),
    ], tempoEvents: [
        ScorePerformanceTempoEvent(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 120,
            endTick: nil,
            endQuarterBPM: nil
        ),
    ])
    stateStore.currentStepIndex = 0

    let effectHandler = CapturingPracticeSessionEffectHandler()
    let service = PracticeManualReplayService(
        sleeper: YieldingSleeper(),
        sequencerPlaybackService: sequencer,
        playbackSequenceBuilder: PlaybackSequenceBuilder(),
        stateStore: stateStore,
        effectHandler: effectHandler
    )

    service.startManualReplay(with: ManualReplayPlan(stepRange: 0 ..< 2))
    for _ in 0 ..< 5 {
        await Task.yield()
    }

    service.shutdown()
    service.shutdown()

    for _ in 0 ..< 10 {
        await Task.yield()
    }

    #expect(stateStore.isManualReplayPlaying == false)
    #expect(sequencer.stopCallCount >= 1)
}
