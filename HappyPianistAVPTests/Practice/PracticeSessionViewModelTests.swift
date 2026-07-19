import Foundation
@testable import HappyPianistAVP
import simd
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
@MainActor
func guidingStartBlockIsEnforcedAtSessionBoundary() {
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )
    viewModel.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)])
    viewModel.setGuidingStartBlocked(true)

    viewModel.startGuidingIfReady()
    #expect(viewModel.state == .ready)

    viewModel.setGuidingStartBlocked(false)
    viewModel.startGuidingIfReady()
    #expect(viewModel.state == .guiding(stepIndex: 0))
}

@Test
@MainActor
func autoplayTimelineKeepsGuideAndNoteOnOnSameTick() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
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
        plan: makeTestScorePerformancePlan(notes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 1),
            TestScorePerformanceNote(midiNote: 62, onTick: 480, offTick: 481),
        ]),
        guideProjection: [firstGuide, secondGuide],
        stepProjection: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
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
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
        tempoEvents: makeTestScorePerformanceTempoEvents(from: tempoMap),
        controllerEvents: makeTestScorePerformanceControllerEvents(from: pedalTimeline),
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
            makeHighlightGuide(id: 2, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62]),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await waitUntil("autoplay started") {
        playbackService.loadedSequences.isEmpty == false
    }

    let stopCountBeforeSkip = playbackService.stopCount
    let loadCountBeforeSkip = playbackService.loadedSequences.count
    viewModel.skip()
    await waitUntil("autoplay restarted after skip") {
        playbackService.loadedSequences.count >= loadCountBeforeSkip + 1
    }

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
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
        tempoEvents: makeTestScorePerformanceTempoEvents(from: tempoMap),
        controllerEvents: makeTestScorePerformanceControllerEvents(from: pedalTimeline),
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
    await waitUntil("initial autoplay load") {
        playbackService.loadedSequences.count == 1
            && playbackService.playStarts.count == 1
            && viewModel.autoplayTimingBaseTick == 0
    }

    #expect(viewModel.autoplayTimingBaseTick != nil)

    viewModel.skip()
    await waitUntil("replacement autoplay load after skip") {
        playbackService.loadedSequences.count == 2
            && playbackService.playStarts.count == 2
            && viewModel.currentStepIndex == 1
            && viewModel.autoplayTimingBaseTick == 480
    }
    await settleTaskQueue()

    #expect(viewModel.autoplayState == .playing)
    #expect(viewModel.autoplayTimingBaseTick == 480)
    viewModel.shutdown()
}

@Test
@MainActor
func markCorrectSchedulesFeedbackResetWithExpectedDuration() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper,
        realPianoContactDetectionService: TestKeyContactDetector(results: [[
            makeTestKeyContactObservation(midiNote: 60, phase: .started),
        ]])
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
    viewModel.startGuidingIfReady()
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty)
    await settleTaskQueue()

    #expect(viewModel.state == .completed)
    #expect(await sleeper.callCount() == 0)

    viewModel.resetSession()
    await settleTaskQueue()
}

@Test
@MainActor
func secondFeedbackCancelsPreviousResetTaskDeterministically() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper,
        realPianoContactDetectionService: TestKeyContactDetector(results: [
            [makeTestKeyContactObservation(midiNote: 60, phase: .started, sequence: 1)],
            [makeTestKeyContactObservation(midiNote: 60, phase: .started, sequence: 2)],
        ])
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 60, onTick: 1),
        ])
    viewModel.startGuidingIfReady()
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty)
    await settleTaskQueue()
    _ = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty)
    await settleTaskQueue()

    #expect(viewModel.state == .completed)
    #expect(await sleeper.callCount() == 0)
}

@Test
@MainActor
func feedbackResetsToNoneAfterSleeperResumes() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper,
        realPianoContactDetectionService: TestKeyContactDetector(results: [[
            makeTestKeyContactObservation(midiNote: 60, phase: .started),
        ]])
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
    viewModel.startGuidingIfReady()
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty)
    await settleTaskQueue()
    #expect(viewModel.state == .completed)
    #expect(await sleeper.callCount() == 0)
}

@Test
@MainActor
func stepsOnlyGuidingStartsWithoutCalibration() {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
    viewModel.startGuidingIfReady()

    #expect(viewModel.currentStep != nil)
    #expect(viewModel.state == .guiding(stepIndex: 0))
}

@Test
@MainActor
func skipAdvancesAndCompletesInStepsOnlyMode() {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 1),
        ])
    viewModel.startGuidingIfReady()

    viewModel.skip()
    #expect(viewModel.currentStepIndex == 1)
    #expect(viewModel.state == .guiding(stepIndex: 1))
    #expect(viewModel.notationViewportTick() == 1)

    viewModel.skip()
    #expect(viewModel.state == .completed)
    #expect(viewModel.notationViewportTick() == 1)
}

@Test
@MainActor
func handleFingerTipPositionsIsNoopWithoutKeyboardGeometry() {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
    viewModel.startGuidingIfReady()

    let detected = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty)
    #expect(detected.isEmpty == true)
    #expect(viewModel.currentStepIndex == 0)
}

@Test
@MainActor
func applyingCalibrationDoesNotResetProgress() {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 1),
        ])
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
func guidingStartUsesPerformancePlanInsteadOfStepSoundFacts() async {
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    let steps = [
        PracticeStep(tick: 0, notes: [
            PracticeStepNote(midiNote: 99, staff: nil, velocity: 1, handAssignment: .unknown),
        ]),
    ]
    let plan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 240),
        TestScorePerformanceNote(midiNote: 64, velocity: 90, onTick: 120, offTick: 360),
    ])
    viewModel.installPreparedSteps(
        steps,
        identity: PracticeSongIdentity(
            songID: plan.sourceScoreIdentity.songID,
            scoreRevision: plan.sourceScoreIdentity.scoreRevision
        ),
        performancePlan: plan,
        notationProjection: .empty,
        measureSpans: [
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 0,
                startTick: 0,
                endTick: 480
            ),
        ]
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(playbackService.oneShots.map(\.midiNotes) == [[60, 64]])
    #expect(playbackService.oneShots.map(\.velocities) == [[80, 90]])
}

@Test
@MainActor
func guidingStartRecordsAudioErrorWhenAudioPlayerThrows() async {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: ThrowingSequencerPlaybackService()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.audioErrorMessage?.isEmpty == false)
}

@Test
@MainActor
func advancingAutoPlaysNextStepSound() async {
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 1),
        ])
    viewModel.startGuidingIfReady()
    viewModel.skip()
    await settleTaskQueue()

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
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [PianoHighlightNote(
                occurrenceID: "fermata-60",
                midiNote: 60,
                staff: 1,
                voice: 1,
                velocity: 80,
                onTick: 0,
                offTick: 480,
                fingerings: [],
                handAssignment: .unknown
            )],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 480,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [PianoHighlightNote(
                occurrenceID: "next-62",
                midiNote: 62,
                staff: 1,
                voice: 1,
                velocity: 80,
                onTick: 480,
                offTick: 960,
                fingerings: [],
                handAssignment: .unknown
            )],
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
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
            TestScorePerformanceNote(midiNote: 64, onTick: 960),
        ],
        tempoEvents: makeTestScorePerformanceTempoEvents(from: tempoMap),
        controllerEvents: makeTestScorePerformanceControllerEvents(from: pedalTimeline),
        highlightGuides: guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await waitUntil("tempo-map autoplay load and final step") {
        playbackService.loadedSequences.count == 1 && viewModel.currentStepIndex == 2
    }

    #expect(playbackService.loadedSequences.count == 1)
    #expect(playbackService.playStarts == [0])
    #expect(viewModel.currentStepIndex == 2)
    viewModel.shutdown()
}

@Test
@MainActor
func autoplaySchedulesPendingOnsetsInsideCurrentStep() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
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
                    fingerings: [],
                    handAssignment: .unknown
                ),
                PianoHighlightNote(
                    occurrenceID: "t30-64",
                    midiNote: 64,
                    staff: 1,
                    voice: 1,
                    velocity: 96,
                    onTick: 30,
                    offTick: 510,
                    fingerings: [],
                    handAssignment: .unknown
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
        plan: makeTestScorePerformancePlan(notes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
            TestScorePerformanceNote(midiNote: 64, onTick: 30, offTick: 510),
        ]),
        guideProjection: highlightGuides,
        stepProjection: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 480, notes: []),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildPerformanceEventSchedule(
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
func autoplayInsertsPlanPauseBeforeAdvancing() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let highlightedNote = PianoHighlightNote(
        occurrenceID: "fermata-60-0-480",
        midiNote: 60,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 0,
        offTick: 480,
        fingerings: [],
        handAssignment: .unknown
    )
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [highlightedNote],
            triggeredNotes: [highlightedNote],
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
        plan: makeTestScorePerformancePlan(
            notes: [TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480)],
            annotations: [ScorePerformanceAnnotation(
                sourceDirectionID: nil,
                performedOccurrenceIndex: 0,
                tick: 480,
                durationTicks: 240,
                kind: .pause,
                text: "fermata",
                provenance: []
            )]
        ),
        guideProjection: guides,
        stepProjection: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
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
        plan: makeTestScorePerformancePlan(
            notes: [],
            controllerEvents: [testPerformanceController(tick: 480, value: 127)]
        ),
        guideProjection: guides,
        stepProjection: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil, handAssignment: .unknown)]),
            PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 62, staff: nil, handAssignment: .unknown)]),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildPerformanceEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)
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
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
            TestScorePerformanceNote(midiNote: 64, onTick: 960),
        ],
        tempoEvents: makeTestScorePerformanceTempoEvents(from: tempoMap),
        controllerEvents: makeTestScorePerformanceControllerEvents(from: pedalTimeline),
        highlightGuides: guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await waitUntil("autoplay started") {
        playbackService.loadedSequences.isEmpty == false
    }

    let loadCountBeforeSkip = playbackService.loadedSequences.count
    let stopCountBeforeSkip = playbackService.stopCount
    viewModel.skip()
    await waitUntil("autoplay restarted after skip") {
        playbackService.loadedSequences.count >= loadCountBeforeSkip + 1
    }

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
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: sleeper,
        realPianoContactDetectionService: TestKeyContactDetector(results: [[
            makeTestKeyContactObservation(midiNote: 60, phase: .started),
        ]])
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ])
    viewModel.setAutoplayEnabled(true)
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )

    _ = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty)
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 0)

    viewModel.resetSession()
    await settleTaskQueue()
}

@Test
@MainActor
func highlightGuideStartsAtFirstTriggerAfterStartGuiding() async {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
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
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ],
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
func clearPreparedSongRemovesSongStateAndPreservesCalibration() async throws {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )
    let calibration = PianoCalibration(
        a0: .zero,
        c8: SIMD3<Float>(1, 0, 0),
        planeHeight: 0
    )
    let geometry = makeDummyKeyboardGeometry()
    viewModel.applyKeyboardGeometry(geometry, calibration: calibration)
    viewModel.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)],
        highlightGuides: [
            makeHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                practiceStepIndex: 0,
                midiNotes: [60]
            ),
        ]
    )
    let identity = try #require(viewModel.songIdentity)
    viewModel.progressGeneration = 7
    viewModel.sessionProgress = SongPracticeProgress(identity: identity, updatedAt: .now)

    viewModel.clearPreparedSong()
    await settleTaskQueue()

    #expect(viewModel.songIdentity == nil)
    #expect(viewModel.steps.isEmpty)
    #expect(viewModel.measureSpans.isEmpty)
    #expect(viewModel.measureIndex == nil)
    #expect(viewModel.activeRange == nil)
    #expect(viewModel.activeRoundConfiguration == nil)
    #expect(viewModel.roundConfigurationController.pendingPassage == nil)
    #expect(viewModel.sessionProgress == nil)
    #expect(viewModel.progressGeneration == nil)
    #expect(viewModel.highlightGuides.isEmpty)
    #expect(viewModel.performancePlan == nil)
    #expect(viewModel.attributeTimeline == nil)
    #expect(viewModel.latestFeedbackEvent == nil)
    #expect(viewModel.autoplayTimeline == .empty)
    #expect(viewModel.currentPianoHighlightGuide == nil)
    #expect(viewModel.currentStepIndex == 0)
    #expect(viewModel.state == .idle)
    #expect(viewModel.calibration == calibration)
    #expect(viewModel.keyboardGeometry == geometry)
}

@Test
@MainActor
func manualAdvanceShowsReleaseOrGapGuideBeforeNextTrigger() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
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
    #expect(viewModel.notationViewportTick() == 480)
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
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
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
        plan: makeTestScorePerformancePlan(notes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
        ]),
        guideProjection: guides,
        stepProjection: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, voice: 1, handAssignment: .unknown)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, voice: 1, handAssignment: .unknown)]),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
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
func autoplaySchedulesNoteOffFromPerformancePlan() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
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
                    fingerings: [],
                    handAssignment: .unknown
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
        plan: makeTestScorePerformancePlan(notes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
        ]),
        guideProjection: guides,
        stepProjection: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 1440, notes: []),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildPerformanceEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

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
        plan: makeTestScorePerformancePlan(
            notes: [TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480)],
            controllerEvents: [
                testPerformanceController(tick: 0, value: 127),
                testPerformanceController(tick: 960, value: 0),
            ]
        ),
        guideProjection: guides,
        stepProjection: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 1440, notes: []),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildPerformanceEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

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
        plan: makeTestScorePerformancePlan(
            notes: [TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480)],
            controllerEvents: [
                testPerformanceController(tick: 0, value: 127),
                testPerformanceController(tick: 480, value: 0),
                testPerformanceController(tick: 480, value: 127),
            ]
        ),
        guideProjection: guides,
        stepProjection: [
            PracticeStep(tick: 0, notes: []),
            PracticeStep(tick: 1440, notes: []),
        ],
        tempoMap: tempoMap,
        practiceHandMode: .both
    )

    let builder = PracticeSequencerSequenceBuilder()
    let schedule = builder.buildPerformanceEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

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
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
        tempoEvents: makeTestScorePerformanceTempoEvents(from: tempoMap),
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
                        fingerings: [],
                        handAssignment: .unknown
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

@Test
@MainActor
func freshScoreDefaultsToFullScoreAtOneHundredPercent() {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )
    let spans = (0 ..< 6).map { index in
        MusicXMLMeasureSpan(
            partID: "P1",
            measureNumber: index + 1,
            sourceMeasureIndex: index,
            sourceMeasureNumberToken: "\(index + 1)",
            occurrenceIndex: index,
            startTick: index * 480,
            endTick: (index + 1) * 480
        )
    }
    viewModel.installTestPerformanceNotes(
        (0 ..< 6).map { index in
            TestScorePerformanceNote(midiNote: 60 + index, onTick: index * 480)
        },
        measureSpans: spans
    )

    #expect(viewModel.activeRoundConfiguration?.passage.start == spans[0].occurrenceID)
    #expect(viewModel.activeRoundConfiguration?.passage.end == spans[5].occurrenceID)
    #expect(viewModel.activeRoundConfiguration?.handMode == .both)
    #expect(viewModel.activeRoundConfiguration?.tempoScale == 1)
    #expect(viewModel.activeRoundConfiguration?.loopEnabled == false)
}

@Test
@MainActor
func changingSongWithEqualStepsReplacesCompletedPassage() {
    let viewModel = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )
    let notes = [TestScorePerformanceNote(midiNote: 60, onTick: 0)]
    let spanA = MusicXMLMeasureSpan(
        partID: "A", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1",
        occurrenceIndex: 0, startTick: 0, endTick: 480
    )
    let spanB = MusicXMLMeasureSpan(
        partID: "B", measureNumber: 9, sourceMeasureIndex: 8, sourceMeasureNumberToken: "9",
        occurrenceIndex: 0, startTick: 0, endTick: 480
    )
    let identityA = PracticeSongIdentity(songID: UUID(), scoreRevision: "a")
    let planA = makeTestScorePerformancePlan(identity: identityA, notes: notes)
    viewModel.installPreparedSteps(
        PracticeStepBuilder().buildSteps(from: planA).steps,
        identity: identityA,
        performancePlan: planA,
        notationProjection: ScoreNotationProjection(
            plan: planA,
            sourceScore: makeTestMusicXMLScore(notes: notes)
        ),
        measureSpans: [spanA]
    )
    viewModel.state = .completed

    let identityB = PracticeSongIdentity(songID: UUID(), scoreRevision: "b")
    let planB = makeTestScorePerformancePlan(identity: identityB, notes: notes)
    viewModel.installPreparedSteps(
        PracticeStepBuilder().buildSteps(from: planB).steps,
        identity: identityB,
        performancePlan: planB,
        notationProjection: ScoreNotationProjection(
            plan: planB,
            sourceScore: makeTestMusicXMLScore(notes: notes)
        ),
        measureSpans: [spanB]
    )

    #expect(viewModel.roundConfigurationController.pendingPassage?.start == spanB.occurrenceID)
    #expect(viewModel.activeRoundConfiguration?.passage.start == spanB.occurrenceID)
    #expect(viewModel.activeRange?.measureSpans == [spanB])
    #expect(viewModel.state == .ready)
}

@MainActor
private func makePracticeSessionViewModel(
    chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
    sleeper: SleeperProtocol,
    sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol? = nil,
    realPianoContactDetectionService: (any KeyContactDetectingProtocol)? = nil
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        chordAttemptAccumulator: chordAttemptAccumulator,
        sleeper: sleeper,
        sequencerPlaybackService: sequencerPlaybackService ?? CapturingSequencerPlaybackService(),
        realPianoContactDetectionService: realPianoContactDetectionService
    )
}

private func settleTaskQueue(iterations: Int = 12) async {
    for _ in 0 ..< iterations {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private func waitUntil(
    _ description: String,
    iterations: Int = 240,
    condition: () -> Bool
) async {
    for _ in 0 ..< iterations {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition(), "Timed out waiting for: \(description)")
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

private func testPerformanceController(tick: Int, value: UInt8) -> ScorePerformanceControllerEvent {
    ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: tick,
        controllerNumber: 64,
        value: value,
        outputCapabilityRequirement: .continuousControlChange
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
            fingerings: [],
            handAssignment: .unknown
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
    let sleeper = PendingSleeper()
    let audioRecognitionService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    playbackService.currentSecondsValue = 0

    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        sequencerPlaybackService: playbackService,
        audioRecognitionService: audioRecognitionService,
        manualAdvanceMode: .measure
    )
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
        ],
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
        measureSpans: [MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 960)]
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

private struct PendingSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

private final class AlwaysMatchChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: true)
    }

    func reset() {}
}

private final class CapturingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    struct OneShot: Equatable {
        let midiNotes: [Int]
        let velocities: [UInt8]
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

    func stop(resetCommands _: [PerformanceTransportCommand]) {
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

    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds: TimeInterval) throws {
        let noteOns = commands.compactMap { command -> (midi: Int, velocity: UInt8)? in
            guard case let .noteOn(midi, velocity) = command.kind else { return nil }
            return (midi, velocity)
        }
        oneShots.append(OneShot(
            midiNotes: noteOns.map(\.midi),
            velocities: noteOns.map(\.velocity),
            durationSeconds: durationSeconds
        ))
    }

    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

private final class ThrowingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {
        throw PracticeAudioError.soundFontMissing(resourceName: "TestSoundFont")
    }

    func execute(commands _: [PracticePlaybackCommand]) throws {}
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

@MainActor
@Test
func reinstallingSamePreparedScoreDiscardsUnappliedDraftConfiguration() throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "same-revision")
    let spans = (0 ..< 6).map { index in
        MusicXMLMeasureSpan(
            partID: "P1",
            measureNumber: index + 1,
            sourceMeasureIndex: index,
            sourceMeasureNumberToken: "\(index + 1)",
            occurrenceIndex: index,
            startTick: index * 480,
            endTick: (index + 1) * 480
        )
    }
    let notes = (0 ..< 6).map { index in
        TestScorePerformanceNote(midiNote: 60 + index, onTick: index * 480)
    }
    let session = makePracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    let plan = makeTestScorePerformancePlan(identity: identity, notes: notes)
    let steps = PracticeStepBuilder().buildSteps(from: plan).steps
    session.installPreparedSteps(
        steps,
        identity: identity,
        performancePlan: plan,
        notationProjection: ScoreNotationProjection(
            plan: plan,
            sourceScore: makeTestMusicXMLScore(notes: notes)
        ),
        measureSpans: spans
    )
    session.roundConfigurationController.pendingHandMode = .left
    session.roundConfigurationController.pendingTempoScale = 0.5
    session.roundConfigurationController.pendingLoopEnabled = true

    session.installPreparedSteps(
        steps,
        identity: identity,
        performancePlan: plan,
        notationProjection: ScoreNotationProjection(
            plan: plan,
            sourceScore: makeTestMusicXMLScore(notes: notes)
        ),
        measureSpans: spans
    )

    let configuration = try #require(session.roundConfigurationController.pendingConfiguration)
    #expect(configuration.handMode == .both)
    #expect(configuration.tempoScale == 1)
    #expect(configuration.loopEnabled == false)
    #expect(configuration.passage.start == spans.first?.occurrenceID)
    #expect(configuration.passage.end == spans.last?.occurrenceID)
}
