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
    private(set) var warmUpCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0
    private(set) var playOneShotCallCount = 0
    private(set) var lastOneShotNotes: [Int] = []
    private(set) var loadedSequences: [PracticeSequencerSequence] = []

    var currentSecondsValue: TimeInterval = 0

    func warmUp() throws {
        warmUpCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func load(sequence: PracticeSequencerSequence) throws {
        loadCallCount += 1
        loadedSequences.append(sequence)
    }

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
    }

    func currentSeconds() -> TimeInterval {
        currentSecondsValue
    }

    func playOneShot(noteOns: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {
        playOneShotCallCount += 1
        lastOneShotNotes = noteOns.map(\.midiNote)
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

@MainActor
private struct PlaybackCoordinatorFixture {
    let service: PracticePlaybackControlService
    let sequencer: FakeSequencerPlaybackService
    let stateStore: PracticeSessionStateStore
    let effectHandler: CapturingPracticeSessionEffectHandler
    let plan: ScorePerformancePlan
}

@MainActor
private func makePlaybackCoordinatorFixture(
    scoreRevision: String,
    currentSeconds: TimeInterval
) -> PlaybackCoordinatorFixture {
    let sequencer = FakeSequencerPlaybackService()
    sequencer.currentSecondsValue = currentSeconds

    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeSessionEffectHandler()

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
    let notes = [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 960),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, offTick: 720),
    ]
    let plan = makeTestScorePerformancePlan(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: scoreRevision),
        notes: notes,
        tempoEvents: [
            ScorePerformanceTempoEvent(
                sourceDirectionID: nil,
                performedOccurrenceIndex: 0,
                tick: 0,
                quarterBPM: 120,
                endTick: nil,
                endQuarterBPM: nil
            ),
        ],
        controllerEvents: makeTestScorePerformanceControllerEvents(
            from: MusicXMLPedalTimeline(events: pedalEvents)
        )
    )
    stateStore.steps = PracticeStepBuilder().buildSteps(from: plan).steps
    stateStore.currentStepIndex = 0
    stateStore.autoplayState = .playing
    stateStore.highlightGuides = stateStore.steps.enumerated().map { index, step in
        let triggeredNotes = plan.noteEvents.filter { $0.performedOnTick == step.tick }.map { note in
            PianoHighlightNote(
                occurrenceID: note.id.description,
                midiNote: note.midiNote,
                staff: note.staff,
                voice: note.voice,
                velocity: note.velocity,
                onTick: note.performedOnTick,
                offTick: note.performedOffTick,
                fingeringText: note.fingeringText,
                handAssignment: note.handAssignment
            )
        }
        return PianoHighlightGuide(
            id: index,
            kind: .trigger,
            tick: step.tick,
            durationTicks: nil,
            practiceStepIndex: index,
            activeNotes: [],
            triggeredNotes: triggeredNotes,
            releasedMIDINotes: []
        )
    }
    stateStore.currentHighlightGuideIndex = 0
    stateStore.performancePlan = plan

    stateStore.autoplayTimeline = AutoplayPerformanceTimeline.build(
        plan: plan,
        guideProjection: stateStore.highlightGuides,
        stepProjection: stateStore.steps,
        tempoMap: stateStore.tempoMap,
        practiceHandMode: .both
    )

    return PlaybackCoordinatorFixture(
        service: PracticePlaybackControlService(
            sleeper: YieldingSleeper(),
            sequencerPlaybackService: sequencer,
            playbackSequenceBuilder: PlaybackSequenceBuilder(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            stateStore: stateStore,
            audioRecognitionService: nil,
            effectHandler: effectHandler,
            audioRecognitionSuppressDuration: 0.6,
            leadInSeconds: 0.05
        ),
        sequencer: sequencer,
        stateStore: stateStore,
        effectHandler: effectHandler,
        plan: plan
    )
}

@Test
@MainActor
func autoplayStartsAndAdvancesStep() async {
    let fixture = makePlaybackCoordinatorFixture(
        scoreRevision: "autoplay-start",
        currentSeconds: 999
    )

    fixture.service.startAutoplayTaskIfNeeded()
    for _ in 0 ..< 10 {
        await Task.yield()
    }

    #expect(fixture.sequencer.loadCallCount == 1)
    #expect(fixture.sequencer.playCallCount == 1)
    #expect(fixture.stateStore.currentStepIndex == 1)
    #expect(fixture.effectHandler.effects.contains(.refreshAudioRecognition))
}

@Test
@MainActor
func shutdownCancelsAutoplayAndPreventsFurtherAdvance() async {
    let fixture = makePlaybackCoordinatorFixture(
        scoreRevision: "autoplay-shutdown",
        currentSeconds: 0
    )

    fixture.service.startAutoplayTaskIfNeeded()
    for _ in 0 ..< 5 {
        await Task.yield()
    }

    fixture.service.shutdown()
    fixture.service.shutdown()

    fixture.sequencer.currentSecondsValue = 999
    for _ in 0 ..< 10 {
        await Task.yield()
    }

    #expect(fixture.stateStore.currentStepIndex == 0)
    #expect(fixture.sequencer.stopCallCount >= 1)
}

@Test
@MainActor
func transportBoundariesResetBeforeApplyingAndAreIdempotent() {
    let plan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 960),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, offTick: 720),
    ])
    let firstID = plan.noteEvents[0].id
    let secondID = plan.noteEvents[1].id
    let reducer = PerformanceTransportReducer()

    let start = reducer.transition(
        from: .idle,
        at: .start(tick: 0, activeEventIDs: [firstID])
    )
    #expect(start.commands == [
        .apply(tick: 0, eventIDs: [firstID], generation: 1),
    ])

    let seek = reducer.transition(
        from: start.state,
        at: .seek(tick: 480, activeEventIDs: [firstID, secondID])
    )
    #expect(seek.commands == [
        .reset(eventIDs: [firstID], reason: .seek, generation: 2),
        .apply(tick: 480, eventIDs: [firstID, secondID], generation: 2),
    ])

    let loop = reducer.transition(
        from: seek.state,
        at: .loop(tick: 0, activeEventIDs: [firstID])
    )
    #expect(loop.commands == [
        .reset(eventIDs: [firstID, secondID], reason: .loop, generation: 3),
        .apply(tick: 0, eventIDs: [firstID], generation: 3),
    ])

    let end = reducer.transition(from: loop.state, at: .end)
    #expect(end.commands == [
        .reset(eventIDs: [firstID], reason: .end, generation: 4),
    ])
    #expect(reducer.transition(from: end.state, at: .end).commands.isEmpty)

    let restarted = reducer.transition(
        from: end.state,
        at: .start(tick: 480, activeEventIDs: [secondID])
    )
    let stop = reducer.transition(from: restarted.state, at: .stop)
    #expect(stop.commands == [
        .reset(eventIDs: [secondID], reason: .stop, generation: 6),
    ])
    #expect(reducer.transition(from: stop.state, at: .stop).commands.isEmpty)
}

@Test
@MainActor
func seekAndLoopRestartWithTargetTickState() async throws {
    let fixture = makePlaybackCoordinatorFixture(
        scoreRevision: "autoplay-boundaries",
        currentSeconds: 0
    )
    fixture.service.startAutoplayTaskIfNeeded()
    for _ in 0 ..< 10 { await Task.yield() }

    fixture.service.seekAutoplay(toStepIndex: 1)
    for _ in 0 ..< 10 { await Task.yield() }

    #expect(fixture.sequencer.stopCallCount == 1)
    #expect(fixture.sequencer.loadCallCount == 2)
    #expect(fixture.sequencer.playCallCount == 2)
    #expect(fixture.stateStore.currentStepIndex == 1)
    let heldID = fixture.plan.noteEvents[0].id.description
    let seekSequence = try #require(fixture.sequencer.loadedSequences.last)
    #expect(seekSequence.events.contains { event in
        event.sourceEventID == heldID && event.kind == .noteOn(midi: 60, velocity: 96)
    })

    fixture.service.loopAutoplay(toStepIndex: 0)
    for _ in 0 ..< 10 { await Task.yield() }

    #expect(fixture.sequencer.stopCallCount == 2)
    #expect(fixture.sequencer.loadCallCount == 3)
    #expect(fixture.sequencer.playCallCount == 3)
    #expect(fixture.stateStore.currentStepIndex == 0)
}
