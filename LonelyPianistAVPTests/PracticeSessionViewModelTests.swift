import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
@MainActor
func autoplayTimelineKeepsGuideAndNoteOnOnSameTick() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let firstGuide = makeHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        practiceStepIndex: 0,
        midiNotes: [60]
    )
    let secondGuide = makeHighlightGuide(
        id: 2,
        kind: .trigger,
        tick: 480,
        practiceStepIndex: 1,
        midiNotes: [62]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        guides: [firstGuide, secondGuide],
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let tick0 = timeline.events.filter { $0.tick == 0 }.map(\.kind)
    let tick480 = timeline.events.filter { $0.tick == 480 }.map(\.kind)

    #expect(tick0.contains { kind in
        if case let .noteOn(midi, _) = kind { return midi == 60 }
        return false
    })
    #expect(tick0.contains { kind in
        if case .advanceGuide = kind { return true }
        return false
    })

    #expect(tick480.contains { kind in
        if case let .noteOn(midi, _) = kind { return midi == 62 }
        return false
    })
    #expect(tick480.contains { kind in
        if case .advanceGuide = kind { return true }
        return false
    })
}

@Test
@MainActor
func skipDuringAutoplayCancelsPendingEventsAndRestartsAtNextStep() async {
    let playbackService = CapturingSequencerPlaybackService()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
            makeHighlightGuide(id: 2, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62]),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    let stopCountBeforeSkip = playbackService.stopCount
    let loadCountBeforeSkip = playbackService.loadedSequences.count
    viewModel.skip()
    await settleTaskQueue()

    #expect(playbackService.stopCount == stopCountBeforeSkip + 1)
    #expect(viewModel.currentStepIndex == 1)
    #expect(playbackService.loadedSequences.count >= loadCountBeforeSkip + 1)
}

@Test
@MainActor
func skipDoesNotLetCancelledAutoplayTaskClearNewTaskReference() async {
    let playbackService = CapturingSequencerPlaybackService()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: [
            makeHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                practiceStepIndex: 0,
                midiNotes: [60],
                noteDurationTicks: 480
            ),
            makeHighlightGuide(
                id: 2,
                kind: .trigger,
                tick: 480,
                practiceStepIndex: 1,
                midiNotes: [62],
                noteDurationTicks: 480
            ),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.autoplayTask != nil)

    viewModel.skip()
    await settleTaskQueue()

    #expect(viewModel.autoplayState == .playing)
    #expect(viewModel.autoplayTask != nil)
}

@Test
@MainActor
func markCorrectSchedulesFeedbackResetWithExpectedDuration() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: ConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(["dummy": .zero])
    await settleTaskQueue()

    #expect(viewModel.feedbackState == .correct)
    #expect(await sleeper.recordedDurations() == [.seconds(0.25)])

    viewModel.resetSession()
    await settleTaskQueue()
}

@Test
@MainActor
func secondFeedbackCancelsPreviousResetTaskDeterministically() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: ConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(["dummy": .zero])
    await settleTaskQueue()
    _ = viewModel.handleFingerTipPositions(["dummy": .zero])
    await settleTaskQueue()

    #expect(await sleeper.callCount() == 2)
    #expect(await sleeper.cancellationCount() == 1)
    #expect(await sleeper.wasRequestCancelled(at: 0) == true)
    #expect(await sleeper.wasRequestCancelled(at: 1) == false)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    #expect(viewModel.feedbackState == .none)
}

@Test
@MainActor
func feedbackResetsToNoneAfterSleeperResumes() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: ConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(["dummy": .zero])
    await settleTaskQueue()
    #expect(viewModel.feedbackState == .correct)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(viewModel.feedbackState == .none)
}

@Test
@MainActor
func stepsOnlyGuidingStartsWithoutCalibration() {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()

    #expect(viewModel.currentStep != nil)
    #expect(viewModel.state == .guiding(stepIndex: 0))
}

@Test
@MainActor
func skipAdvancesAndCompletesInStepsOnlyMode() {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()

    viewModel.skip()
    #expect(viewModel.currentStepIndex == 1)
    #expect(viewModel.state == .guiding(stepIndex: 1))

    viewModel.skip()
    #expect(viewModel.state == .completed)
}

@Test
@MainActor
func handleFingerTipPositionsIsNoopWithoutKeyboardGeometry() {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: ConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()

    let detected = viewModel.handleFingerTipPositions(["dummy": .zero])
    #expect(detected.isEmpty == true)
    #expect(viewModel.currentStepIndex == 0)
}

@Test
@MainActor
func applyingCalibrationDoesNotResetProgress() {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    viewModel.skip()
    #expect(viewModel.currentStepIndex == 1)

    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    #expect(viewModel.currentStepIndex == 1)
    #expect(viewModel.state == .guiding(stepIndex: 1))
}

@Test
@MainActor
func guidingStartAutoPlaysCurrentStepSound() {
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [
                PracticeStepNote(midiNote: 60, staff: nil),
                PracticeStepNote(midiNote: 64, staff: nil),
            ]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()

    #expect(playbackService.oneShots.map(\.midiNotes) == [[60, 64]])
}

@Test
@MainActor
func guidingStartRecordsAudioErrorWhenAudioPlayerThrows() async {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: ThrowingSequencerPlaybackService()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.audioErrorMessage?.isEmpty == false)
}

@Test
@MainActor
func advancingAutoPlaysNextStepSound() {
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    viewModel.skip()

    #expect(playbackService.oneShots.map(\.midiNotes) == [[60], [62]])
}

@Test
@MainActor
func autoplaySchedulesAndAdvancesStepsUsingTempoMap() async {
    let playbackService = CapturingSequencerPlaybackService()
    playbackService.currentSecondsValue = 999
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 480,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 3,
            kind: .trigger,
            tick: 960,
            durationTicks: nil,
            practiceStepIndex: 2,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
            PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(playbackService.loadedSequences.count == 1)
    #expect(playbackService.playStarts == [0])
    #expect(viewModel.currentStepIndex == 2)
}

@Test
@MainActor
func autoplaySchedulesPendingOnsetsInsideCurrentStep() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])

    let highlightGuides: [PianoHighlightGuide] = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [
                PianoHighlightNote(
                    occurrenceID: "t0-60",
                    midiNote: 60,
                    staff: 1,
                    voice: 1,
                    velocity: 96,
                    onTick: 0,
                    offTick: 480,
                    fingeringText: nil
                ),
                PianoHighlightNote(
                    occurrenceID: "t30-64",
                    midiNote: 64,
                    staff: 1,
                    voice: 1,
                    velocity: 96,
                    onTick: 30,
                    offTick: 510,
                    fingeringText: nil
                ),
            ],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 480,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: highlightGuides,
        steps: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 480, notes: []),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildAudioEventSchedule(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 0
    )

    let noteOns = schedule.compactMap { event -> (midi: Int, time: TimeInterval)? in
        guard case let .noteOn(midi, _) = event.kind else { return nil }
        return (midi: midi, time: event.timeSeconds)
    }

    #expect(noteOns.map(\.midi) == [60, 64])
    #expect(abs(noteOns[0].time - 0.0) < 1e-9)
    #expect(abs(noteOns[1].time - 0.03125) < 1e-9)
}

@Test
@MainActor
func autoplayInsertsFermataHoldBeforeAdvancingWhenTimelineProvided() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(
        fermataEvents: [
            MusicXMLFermataEvent(
                tick: 0,
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: 1),
                source: .noteNotations
            ),
        ],
        notes: [
            MusicXMLNoteEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                durationTicks: 480,
                midiNote: 60,
                isRest: false,
                isChord: false,
                tieStart: false,
                tieStop: false,
                staff: 1,
                voice: 1
            ),
        ]
    )
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 480,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let pauseAt480 = timeline.events.first { event in
        event.tick == 480 && {
            if case .pauseSeconds = event.kind { return true }
            return false
        }()
    }

    #expect(pauseAt480 != nil)
    if case let .pauseSeconds(seconds)? = pauseAt480?.kind {
        #expect(abs(seconds - 0.25) < 1e-9)
    }
}

@Test
@MainActor
func autoplaySchedulesPedalChangesBetweenSteps() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 480,
                kind: .start,
                isDown: true,
                timeOnlyPasses: nil
            ),
        ]
    )
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 960,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildAudioEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)
    let pedalChanges = schedule.compactMap { event -> (value: UInt8, time: TimeInterval)? in
        guard case let .controlChange(controller, value) = event.kind, controller == 64 else { return nil }
        return (value: value, time: event.timeSeconds)
    }

    #expect(pedalChanges.first?.value == 127)
    #expect(abs((pedalChanges.first?.time ?? 0) - 0.5) < 1e-9)
}

@Test
@MainActor
func autoplaySkipCancelsPendingSleepAndRestartsScheduling() async {
    let playbackService = CapturingSequencerPlaybackService()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 480,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 3,
            kind: .trigger,
            tick: 960,
            durationTicks: nil,
            practiceStepIndex: 2,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
            PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    let loadCountBeforeSkip = playbackService.loadedSequences.count
    let stopCountBeforeSkip = playbackService.stopCount
    viewModel.skip()
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 1)
    #expect(playbackService.stopCount == stopCountBeforeSkip + 1)
    #expect(playbackService.loadedSequences.count >= loadCountBeforeSkip + 1)

    viewModel.setAutoplayEnabled(false)
    await settleTaskQueue()
}

@Test
@MainActor
func autoplayDoesNotAdvanceOnMatch() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: ConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(["dummy": .zero])
    await settleTaskQueue()

    #expect(viewModel.feedbackState == .none)
    #expect(viewModel.currentStepIndex == 0)

    viewModel.resetSession()
    await settleTaskQueue()
}

@Test
@MainActor
func highlightGuideStartsAtFirstTriggerAfterStartGuiding() async {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, voice: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, voice: 1)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
            makeHighlightGuide(id: 2, kind: .gap, tick: 240, practiceStepIndex: nil, midiNotes: [], released: [60]),
            makeHighlightGuide(id: 3, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62]),
        ]
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide?.kind == .trigger)
    #expect(viewModel.currentPianoHighlightGuide?.tick == 0)
    #expect(viewModel.currentPianoHighlightGuide?.practiceStepIndex == 0)
    #expect(viewModel.currentPianoHighlightGuide?.highlightedMIDINotes == [60])
}

@Test
@MainActor
func resetSessionClearsCurrentHighlightGuide() async {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, voice: 1)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
        ]
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide != nil)

    viewModel.resetSession()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide == nil)
}

@Test
@MainActor
func manualAdvanceShowsReleaseOrGapGuideBeforeNextTrigger() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, voice: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, voice: 1)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
            makeHighlightGuide(
                id: 2,
                kind: .release,
                tick: 240,
                practiceStepIndex: nil,
                midiNotes: [60],
                released: [60]
            ),
            makeHighlightGuide(id: 3, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62]),
        ]
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    #expect(viewModel.currentPianoHighlightGuide?.kind == .trigger)

    viewModel.skip()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide?.kind == .release)
    #expect(await sleeper.callCount() == 1)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide?.kind == .trigger)
    #expect(viewModel.currentPianoHighlightGuide?.practiceStepIndex == 1)
}

@Test
@MainActor
func resetCancelsPendingManualHighlightTransition() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, voice: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, voice: 1)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
            makeHighlightGuide(id: 2, kind: .gap, tick: 240, practiceStepIndex: nil, midiNotes: [], released: [60]),
            makeHighlightGuide(id: 3, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62]),
        ]
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    viewModel.skip()
    await settleTaskQueue()

    #expect(await sleeper.callCount() == 1)
    viewModel.resetSession()
    await settleTaskQueue()

    #expect(await sleeper.cancellationCount() == 1)
    #expect(viewModel.currentPianoHighlightGuide == nil)
}

@Test
@MainActor
func autoplayAdvancesHighlightGuidesByTick() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])

    let guides: [PianoHighlightGuide] = [
        makeHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            practiceStepIndex: 0,
            midiNotes: [60],
            noteDurationTicks: 480
        ),
        makeHighlightGuide(id: 2, kind: .gap, tick: 120, practiceStepIndex: nil, midiNotes: [], released: [60]),
        makeHighlightGuide(id: 3, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62]),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, voice: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, voice: 1)]),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    var cursor = AutoplayTimelineTimeCursor(
        timeline: timeline,
        tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
        startTick: 0
    )

    #expect(cursor.advance(toSeconds: 0).contains(.guide(index: 0, guideID: 1)))
    #expect(cursor.advance(toSeconds: 0.124) == [])
    #expect(cursor.advance(toSeconds: 0.125).contains(.guide(index: 1, guideID: 2)))
}

@Test
@MainActor
func autoplaySchedulesNoteOffUsingNoteSpans() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides: [PianoHighlightGuide] = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [
                PianoHighlightNote(
                    occurrenceID: "t0-60",
                    midiNote: 60,
                    staff: 1,
                    voice: 1,
                    velocity: 96,
                    onTick: 0,
                    offTick: 480,
                    fingeringText: nil
                ),
            ],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 1440,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 1440, notes: []),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildAudioEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

    let noteOff = schedule.first { event in
        if case let .noteOff(midi) = event.kind {
            return midi == 60
        }
        return false
    }

    #expect(noteOff != nil)
    #expect(abs((noteOff?.timeSeconds ?? 0) - 0.5) < 1e-9)
}

@Test
@MainActor
func autoplayDefersNoteOffWhilePedalIsDownAndReleasesOnPedalUp() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                kind: .start,
                isDown: true,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 960,
                kind: .stop,
                isDown: false,
                timeOnlyPasses: nil
            ),
        ]
    )
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides: [PianoHighlightGuide] = [
        makeHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            practiceStepIndex: 0,
            midiNotes: [60],
            noteDurationTicks: 480
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 1440,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 1440, notes: []),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildAudioEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

    let pedalChanges = schedule.compactMap { event -> (value: UInt8, time: TimeInterval)? in
        guard case let .controlChange(controller, value) = event.kind, controller == 64 else { return nil }
        return (value: value, time: event.timeSeconds)
    }
    let noteOff = schedule.first { event in
        if case let .noteOff(midi) = event.kind { return midi == 60 }
        return false
    }

    #expect(pedalChanges.contains { $0.value == 127 && abs($0.time - 0.0) < 1e-9 })
    #expect(pedalChanges.contains { $0.value == 0 && abs($0.time - 1.0) < 1e-9 })
    #expect(noteOff != nil)
    #expect(abs((noteOff?.timeSeconds ?? 0) - 0.5) < 1e-9)
}

@Test
@MainActor
func autoplayReleasesPendingNotesOnPedalChangeTickEvenIfPedalStaysDown() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                kind: .start,
                isDown: true,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 480,
                kind: .change,
                isDown: false,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 480,
                kind: .change,
                isDown: true,
                timeOnlyPasses: nil
            ),
        ]
    )
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides: [PianoHighlightGuide] = [
        makeHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            practiceStepIndex: 0,
            midiNotes: [60],
            noteDurationTicks: 480
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 1440,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 1440, notes: []),
        ],
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildAudioEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

    let pedalChangesAtHalfSecond = schedule.compactMap { event -> UInt8? in
        guard abs(event.timeSeconds - 0.5) < 1e-9 else { return nil }
        guard case let .controlChange(controller, value) = event.kind, controller == 64 else { return nil }
        return value
    }
    let noteOffAtHalfSecond = schedule.contains { event in
        abs(event.timeSeconds - 0.5) < 1e-9 && {
            if case let .noteOff(midi) = event.kind { return midi == 60 }
            return false
        }()
    }

    #expect(pedalChangesAtHalfSecond == [0, 127])
    #expect(noteOffAtHalfSecond == true)
}

@Test
@MainActor
func disablingAutoplayStopsAudioAndClearsPendingScheduling() async {
    let playbackService = CapturingSequencerPlaybackService()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: MusicXMLPedalTimeline(events: []),
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        noteSpans: [
            MusicXMLNoteSpan(midiNote: 60, staff: 1, voice: 1, onTick: 0, offTick: 480),
        ],
        highlightGuides: [
            PianoHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                durationTicks: nil,
                practiceStepIndex: 0,
                activeNotes: [],
                triggeredNotes: [
                    PianoHighlightNote(
                        occurrenceID: "t0-60",
                        midiNote: 60,
                        staff: 1,
                        voice: 1,
                        velocity: 96,
                        onTick: 0,
                        offTick: 480,
                        fingeringText: nil
                    ),
                ],
                releasedMIDINotes: []
            ),
            PianoHighlightGuide(
                id: 2,
                kind: .trigger,
                tick: 480,
                durationTicks: nil,
                practiceStepIndex: 1,
                activeNotes: [],
                triggeredNotes: [],
                releasedMIDINotes: []
            ),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    let stopCountBeforeDisable = playbackService.stopCount
    viewModel.setAutoplayEnabled(false)
    await settleTaskQueue()

    #expect(playbackService.stopCount == stopCountBeforeDisable + 1)
}

@MainActor
private func makePracticeSessionViewModel(
    pressDetectionService: PressDetectionServiceProtocol,
    chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
    sleeper: SleeperProtocol,
    sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol? = nil
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: pressDetectionService,
        chordAttemptAccumulator: chordAttemptAccumulator,
        sleeper: sleeper,
        sequencerPlaybackService: sequencerPlaybackService ?? CapturingSequencerPlaybackService()
    )
}

private func settleTaskQueue(iterations: Int = 12) async {
    for _ in 0 ..< iterations {
        await Task.yield()
    }
}

private func makeHighlightGuide(
    id: Int,
    kind: PianoHighlightGuideKind,
    tick: Int,
    practiceStepIndex: Int?,
    midiNotes: Set<Int>,
    released: Set<Int> = []
) -> PianoHighlightGuide {
    makeHighlightGuide(
        id: id,
        kind: kind,
        tick: tick,
        practiceStepIndex: practiceStepIndex,
        midiNotes: midiNotes,
        released: released,
        noteDurationTicks: 1
    )
}

private func makeHighlightGuide(
    id: Int,
    kind: PianoHighlightGuideKind,
    tick: Int,
    practiceStepIndex: Int?,
    midiNotes: Set<Int>,
    released: Set<Int> = [],
    noteDurationTicks: Int
) -> PianoHighlightGuide {
    let notes = midiNotes.sorted().enumerated().map { index, midi in
        PianoHighlightNote(
            occurrenceID: "test-\(id)-\(tick)-\(index)-\(midi)",
            midiNote: midi,
            staff: 1,
            voice: 1,
            velocity: 96,
            onTick: tick,
            offTick: tick + max(1, noteDurationTicks),
            fingeringText: nil
        )
    }
    let activeNotes = (kind == .trigger || kind == .sustain || kind == .release) ? notes : []
    let triggeredNotes = (kind == .trigger) ? notes : []
    return PianoHighlightGuide(
        id: id,
        kind: kind,
        tick: tick,
        durationTicks: nil,
        practiceStepIndex: practiceStepIndex,
        activeNotes: activeNotes,
        triggeredNotes: triggeredNotes,
        releasedMIDINotes: released
    )
}

private func makeDummyKeyboardGeometry() -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.0, 0.0),
        c8World: SIMD3<Float>(1.0, 0.0, 0.0),
        planeHeight: 0.0
    )!
    return PianoKeyboardGeometry(frame: frame, keys: [])
}

@Test
@MainActor
func enablingAutoplayStopsManualReplayWithoutResumingAudioRecognition() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let sleeper = PendingSleeper()
    let audioRecognitionService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    playbackService.currentSecondsValue = 0

    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        sequencerPlaybackService: playbackService,
        audioRecognitionService: audioRecognitionService,
        manualAdvanceModeProvider: { .measure }
    )
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: MusicXMLPedalTimeline(events: []),
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        highlightGuides: [
            PianoHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                durationTicks: nil,
                practiceStepIndex: 0,
                activeNotes: [],
                triggeredNotes: [],
                releasedMIDINotes: []
            ),
            PianoHighlightGuide(
                id: 2,
                kind: .trigger,
                tick: 480,
                durationTicks: nil,
                practiceStepIndex: 1,
                activeNotes: [],
                triggeredNotes: [],
                releasedMIDINotes: []
            ),
        ],
        measureSpans: [MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 960)]
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    #expect(audioRecognitionService.startCalls.isEmpty == false)

    viewModel.replayCurrentUnit()
    await settleTaskQueue()
    #expect(viewModel.isManualReplayPlaying)

    viewModel.setAutoplayEnabled(true)
    await settleTaskQueue()

    #expect(viewModel.isManualReplayPlaying == false)
    #expect(viewModel.autoplayState == .playing)
    #expect(audioRecognitionService.stopCallCount > 0)
}

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private struct PendingSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

private struct ConstantPressDetectionService: PressDetectionServiceProtocol {
    let pressedNotes: Set<Int>

    init(pressedNotes: Set<Int>) {
        self.pressedNotes = pressedNotes
    }

    init(pressedNotes: [Int]) {
        self.pressedNotes = Set(pressedNotes)
    }

    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        pressedNotes
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> Bool {
        false
    }

    func reset() {}
}

private final class AlwaysMatchChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> Bool {
        true
    }

    func reset() {}
}

private final class CapturingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    struct OneShot: Equatable {
        let midiNotes: [Int]
        let durationSeconds: TimeInterval
    }

    private(set) var warmUpCount = 0
    private(set) var stopCount = 0
    private(set) var loadedSequences: [PracticeSequencerSequence] = []
    private(set) var playStarts: [TimeInterval] = []
    private(set) var oneShots: [OneShot] = []
    var currentSecondsValue: TimeInterval = 0

    func warmUp() throws {
        warmUpCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func load(sequence: PracticeSequencerSequence) throws {
        loadedSequences.append(sequence)
    }

    func play(fromSeconds start: TimeInterval) throws {
        playStarts.append(start)
    }

    func currentSeconds() -> TimeInterval {
        currentSecondsValue
    }

    func playOneShot(midiNotes: [Int], durationSeconds: TimeInterval) throws {
        oneShots.append(OneShot(midiNotes: midiNotes, durationSeconds: durationSeconds))
    }
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private final class ThrowingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {
        throw PracticeAudioError.soundFontMissing(resourceName: "TestSoundFont")
    }
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private actor ControllableSleeper: SleeperProtocol {
    private var requests: [UUID] = []
    private var durationsByID: [UUID: Duration] = [:]
    private var continuationsByID: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var cancelledRequestIDs: Set<UUID> = []

    func sleep(for duration: Duration) async throws {
        let requestID = UUID()
        requests.append(requestID)
        durationsByID[requestID] = duration

        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                continuationsByID[requestID] = continuation
            }
        }, onCancel: {
            Task {
                await self.handleCancellation(for: requestID)
            }
        })
    }

    func recordedDurations() -> [Duration] {
        requests.compactMap { durationsByID[$0] }
    }

    func callCount() -> Int {
        requests.count
    }

    func cancellationCount() -> Int {
        cancelledRequestIDs.count
    }

    func wasRequestCancelled(at index: Int) -> Bool {
        guard requests.indices.contains(index) else { return false }
        return cancelledRequestIDs.contains(requests[index])
    }

    func resumeOldestPending() {
        guard
            let requestID = requests.first(where: { continuationsByID[$0] != nil }),
            let continuation = continuationsByID.removeValue(forKey: requestID)
        else {
            return
        }
        continuation.resume()
    }

    private func handleCancellation(for requestID: UUID) {
        cancelledRequestIDs.insert(requestID)
        if let continuation = continuationsByID.removeValue(forKey: requestID) {
            continuation.resume(throwing: CancellationError())
        }
    }
}
