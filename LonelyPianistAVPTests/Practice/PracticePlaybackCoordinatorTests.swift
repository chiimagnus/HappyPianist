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

@MainActor
private final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var warmUpCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0
    private(set) var playOneShotCallCount = 0
    private(set) var lastOneShotNotes: [Int] = []

    var currentSecondsValue: TimeInterval = 0

    func warmUp() throws {
        warmUpCallCount += 1
    }

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

    func playOneShot(midiNotes: [Int], durationSeconds _: TimeInterval) throws {
        playOneShotCallCount += 1
        lastOneShotNotes = midiNotes
    }

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
func autoplayStartsAndAdvancesStep() async {
    let sequencer = FakeSequencerPlaybackService()
    sequencer.currentSecondsValue = 999

    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()

    stateStore.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
    stateStore.currentStepIndex = 0
    stateStore.autoplayState = .playing
    stateStore.tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )

    let pedalEvents = [
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            kind: .start,
            isDown: false,
            timeOnlyPasses: nil
        ),
    ]
    stateStore.pedalTimeline = MusicXMLPedalTimeline(events: pedalEvents)
    stateStore.fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])

    let triggerNote = PianoHighlightNote(
        occurrenceID: "n0",
        midiNote: 60,
        staff: 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 240,
        fingeringText: nil
    )
    stateStore.highlightGuides = [
        PianoHighlightGuide(
            id: 0,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [triggerNote],
            releasedMIDINotes: []
        ),
    ]

    stateStore.autoplayTimeline = AutoplayPerformanceTimeline.build(
        guides: stateStore.highlightGuides,
        steps: stateStore.steps,
        pedalTimeline: stateStore.pedalTimeline!,
        fermataTimeline: stateStore.fermataTimeline!,
        tempoMap: stateStore.tempoMap,
        practiceHandMode: .both
    )

    let service = PracticePlaybackControlService(
        sleeper: YieldingSleeper(),
        sequencerPlaybackService: sequencer,
        playbackSequenceBuilder: PlaybackSequenceBuilder(),
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        stateStore: stateStore,
        audioRecognitionService: nil,
        effectHandler: effectHandler,
        audioRecognitionSuppressDuration: 0.6,
        leadInSeconds: 0.05,
        handModeProvider: { .both }
    )

    service.startAutoplayTaskIfNeeded()
    for _ in 0..<10 { await Task.yield() }

    #expect(sequencer.loadCallCount == 1)
    #expect(sequencer.playCallCount == 1)
    #expect(stateStore.currentStepIndex == 1)
    #expect(effectHandler.effects.contains(.refreshAudioRecognition))
}

@Test
@MainActor
func shutdownCancelsAutoplayAndPreventsFurtherAdvance() async {
    let sequencer = FakeSequencerPlaybackService()
    sequencer.currentSecondsValue = 0

    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()

    stateStore.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
    stateStore.currentStepIndex = 0
    stateStore.autoplayState = .playing
    stateStore.tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )

    let pedalEvents = [
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            kind: .start,
            isDown: false,
            timeOnlyPasses: nil
        ),
    ]
    stateStore.pedalTimeline = MusicXMLPedalTimeline(events: pedalEvents)
    stateStore.fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])

    let triggerNote = PianoHighlightNote(
        occurrenceID: "n0",
        midiNote: 60,
        staff: 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 240,
        fingeringText: nil
    )
    stateStore.highlightGuides = [
        PianoHighlightGuide(
            id: 0,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [triggerNote],
            releasedMIDINotes: []
        ),
    ]

    stateStore.autoplayTimeline = AutoplayPerformanceTimeline.build(
        guides: stateStore.highlightGuides,
        steps: stateStore.steps,
        pedalTimeline: stateStore.pedalTimeline!,
        fermataTimeline: stateStore.fermataTimeline!,
        tempoMap: stateStore.tempoMap,
        practiceHandMode: .both
    )

    let service = PracticePlaybackControlService(
        sleeper: YieldingSleeper(),
        sequencerPlaybackService: sequencer,
        playbackSequenceBuilder: PlaybackSequenceBuilder(),
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        stateStore: stateStore,
        audioRecognitionService: nil,
        effectHandler: effectHandler,
        audioRecognitionSuppressDuration: 0.6,
        leadInSeconds: 0.05,
        handModeProvider: { .both }
    )

    service.startAutoplayTaskIfNeeded()
    for _ in 0..<5 { await Task.yield() }

    service.shutdown()
    service.shutdown()

    sequencer.currentSecondsValue = 999
    for _ in 0..<10 { await Task.yield() }

    #expect(stateStore.currentStepIndex == 0)
    #expect(sequencer.stopCallCount >= 1)
}
