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

    var currentSecondsValue: TimeInterval = 0

    func warmUp() throws {}

    func stop() {
        stopCallCount += 1
    }

    func load(sequence _: PracticeSequencerSequence) throws {
        loadCallCount += 1
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

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
@MainActor
func manualReplayStopsAudioRecognitionAndRestoresAfterCompletion() async {
    let sequencer = FakeSequencerPlaybackService()
    sequencer.currentSecondsValue = 999

    let stateStore = PracticeSessionStateStore()
    stateStore.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
    ]
    stateStore.performancePlan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, offTick: 960),
    ])
    stateStore.currentStepIndex = 0
    stateStore.tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
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

    service.startManualReplay(with: ManualReplayPlan(stepRange: 0 ..< 2))
    for _ in 0 ..< 20 {
        await Task.yield()
    }

    #expect(effectHandler.effects.contains(.stopAudioRecognition))
    #expect(effectHandler.effects.contains(.refreshAudioRecognition))
    #expect(stateStore.isManualReplayPlaying == false)
    #expect(stateStore.currentStepIndex == 0)
    #expect(sequencer.loadCallCount == 1)
    #expect(sequencer.playCallCount == 1)
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
    ])
    stateStore.currentStepIndex = 0
    stateStore.tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )

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
