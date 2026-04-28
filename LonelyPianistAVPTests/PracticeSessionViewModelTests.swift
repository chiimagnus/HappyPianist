import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
@MainActor
func autoplayTimelineKeepsGuideAndNoteOnOnSameTick() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
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

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: [firstGuide, secondGuide]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(output.recordedNoteOns.map(\.midi) == [60])
    #expect(viewModel.currentPianoHighlightGuide?.id == 1)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(output.recordedNoteOns.map(\.midi).contains(62))
    #expect(viewModel.currentPianoHighlightGuide?.id == 2)
}

@Test
@MainActor
func skipDuringAutoplayCancelsPendingEventsAndRestartsAtNextStep() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
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

    let allNotesOffBeforeSkip = output.allNotesOffCount
    viewModel.skip()
    await settleTaskQueue()

    #expect(output.allNotesOffCount == allNotesOffBeforeSkip + 1)
    #expect(viewModel.currentStepIndex == 1)
    #expect(output.recordedNoteOns.map(\.midi).contains(62))
}

@Test
@MainActor
func skipDoesNotLetCancelledAutoplayTaskClearNewTaskReference() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
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
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60], noteDurationTicks: 480),
            makeHighlightGuide(id: 2, kind: .trigger, tick: 480, practiceStepIndex: 1, midiNotes: [62], noteDurationTicks: 480),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(await sleeper.callCount() == 1)

    viewModel.skip()
    await settleTaskQueue()

    #expect(await sleeper.cancellationCount() == 1)
    #expect(await sleeper.callCount() == 2)

    viewModel.setAutoplayEnabled(true)
    await settleTaskQueue()

    #expect(await sleeper.callCount() == 2)
    #expect(viewModel.autoplayState == .playing)
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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])
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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])
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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])
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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])
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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
    ])
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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])
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
        sleeper: TaskSleeper(),
        noteAudioPlayer: nil
    )

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
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
func guidingStartAutoPlaysCurrentStepSound() {
    let audioPlayer = CapturingPracticeNoteAudioPlayer()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        noteAudioPlayer: audioPlayer
    )

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [
            PracticeStepNote(midiNote: 60, staff: nil),
            PracticeStepNote(midiNote: 64, staff: nil),
        ]),
    ])
    viewModel.startGuidingIfReady()

    #expect(audioPlayer.recordedPlays == [[60, 64]])
}

@Test
@MainActor
func guidingStartRecordsAudioErrorWhenAudioPlayerThrows() async {
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        noteAudioPlayer: ThrowingPracticeNoteAudioPlayer()
    )

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.audioErrorMessage?.isEmpty == false)
}

@Test
@MainActor
func advancingAutoPlaysNextStepSound() {
    let audioPlayer = CapturingPracticeNoteAudioPlayer()
    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        noteAudioPlayer: audioPlayer
    )

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 1, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
    ])
    viewModel.startGuidingIfReady()
    viewModel.skip()

    #expect(audioPlayer.recordedPlays == [[60], [62]])
}

@Test
@MainActor
func autoplaySchedulesAndAdvancesStepsUsingTempoMap() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides = [
        PianoHighlightGuide(id: 1, kind: .trigger, tick: 0, durationTicks: nil, practiceStepIndex: 0, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        PianoHighlightGuide(id: 2, kind: .trigger, tick: 480, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        PianoHighlightGuide(id: 3, kind: .trigger, tick: 960, durationTicks: nil, practiceStepIndex: 2, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
    ]

    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
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

    #expect(await sleeper.recordedDurations() == [.seconds(0.5)])

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)

    await settleTaskQueue()
    #expect(await sleeper.recordedDurations() == [.seconds(0.5), .seconds(0.5)])

    viewModel.setAutoplayEnabled(false)
    await settleTaskQueue()
    #expect(await sleeper.cancellationCount() == 1)
}

@Test
@MainActor
func autoplaySchedulesPendingOnsetsInsideCurrentStep() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let output = CapturingMIDINoteOutput()

    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [
                PracticeStepNote(midiNote: 60, staff: 1, onTickOffset: 0),
                PracticeStepNote(midiNote: 64, staff: 1, onTickOffset: 30),
            ]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 67, staff: 1)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        noteSpans: [
            MusicXMLNoteSpan(midiNote: 60, staff: 1, voice: 1, onTick: 0, offTick: 480),
            MusicXMLNoteSpan(midiNote: 64, staff: 1, voice: 1, onTick: 30, offTick: 510),
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
    )

    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(output.recordedNoteOns.map(\.midi) == [60])
    #expect(await sleeper.recordedDurations() == [.seconds(0.03125)])

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(output.recordedNoteOns.map(\.midi) == [60, 64])
    #expect(await sleeper.recordedDurations() == [.seconds(0.03125), .seconds(0.46875)])
}

@Test
@MainActor
func autoplayInsertsFermataHoldBeforeAdvancingWhenTimelineProvided() async {
    let sleeper = ControllableSleeper()
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
        PianoHighlightGuide(id: 1, kind: .trigger, tick: 0, durationTicks: nil, practiceStepIndex: 0, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        PianoHighlightGuide(id: 2, kind: .trigger, tick: 480, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
    ]

    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: guides
    )

    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(await sleeper.recordedDurations() == [.seconds(0.5)])

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 0)
    #expect(await sleeper.recordedDurations() == [.seconds(0.5), .seconds(0.25)])

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func autoplaySchedulesPedalChangesBetweenSteps() async {
    let sleeper = ControllableSleeper()
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
        PianoHighlightGuide(id: 1, kind: .trigger, tick: 0, durationTicks: nil, practiceStepIndex: 0, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        PianoHighlightGuide(id: 2, kind: .trigger, tick: 960, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
    ]

    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        highlightGuides: guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(await sleeper.recordedDurations() == [.seconds(0.5)])

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 0)
    #expect(viewModel.isSustainPedalDown == true)

    await settleTaskQueue()
    #expect(await sleeper.recordedDurations() == [.seconds(0.5), .seconds(0.5)])

    await sleeper.resumeOldestPending()
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func autoplaySkipCancelsPendingSleepAndRestartsScheduling() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let guides = [
        PianoHighlightGuide(id: 1, kind: .trigger, tick: 0, durationTicks: nil, practiceStepIndex: 0, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        PianoHighlightGuide(id: 2, kind: .trigger, tick: 480, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        PianoHighlightGuide(id: 3, kind: .trigger, tick: 960, durationTicks: nil, practiceStepIndex: 2, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
    ]

    let viewModel = makePracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
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

    #expect(await sleeper.callCount() == 1)
    viewModel.skip()
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 1)
    #expect(await sleeper.callCount() == 2)
    #expect(await sleeper.cancellationCount() == 1)
    #expect(await sleeper.wasRequestCancelled(at: 0) == true)
    #expect(await sleeper.wasRequestCancelled(at: 1) == false)

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

    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
    ])
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
        tempoMap: nil,
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
        tempoMap: nil,
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
        tempoMap: nil,
        pedalTimeline: nil,
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(id: 1, kind: .trigger, tick: 0, practiceStepIndex: 0, midiNotes: [60]),
            makeHighlightGuide(id: 2, kind: .release, tick: 240, practiceStepIndex: nil, midiNotes: [60], released: [60]),
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
        tempoMap: nil,
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
func autoplayAdvancesHighlightGuidesByTick() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
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
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        noteSpans: [],
        highlightGuides: [
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
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide?.tick == 0)
    #expect(await sleeper.callCount() >= 1)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(viewModel.currentPianoHighlightGuide?.tick == 120)
    #expect(viewModel.currentPianoHighlightGuide?.kind == .gap)

    viewModel.resetSession()
    await settleTaskQueue()
}

@Test
@MainActor
func autoplaySchedulesNoteOffUsingNoteSpans() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1440, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
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
                tick: 1440,
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

    #expect(output.recordedNoteOns.map(\.midi) == [60])
    #expect(output.recordedNoteOffs.isEmpty == true)

    for _ in 0 ..< 6 {
        await sleeper.resumeOldestPending()
        await settleTaskQueue()
        if output.recordedNoteOffs.contains(60) {
            break
        }
    }

    #expect(output.recordedNoteOffs.contains(60) == true)
}

@Test
@MainActor
func autoplayDefersNoteOffWhilePedalIsDownAndReleasesOnPedalUp() async {
    let sleeper = ControllableSleeper()
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

    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1440, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                practiceStepIndex: 0,
                midiNotes: [60],
                noteDurationTicks: 480
            ),
            PianoHighlightGuide(id: 2, kind: .trigger, tick: 1440, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(output.recordedNoteOns.map(\.midi) == [60])
    #expect(output.recordedNoteOffs.contains(60) == false)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(output.recordedNoteOffs.contains(60) == false)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(output.recordedNoteOffs.contains(60) == true)
}

@Test
@MainActor
func autoplayReleasesPendingNotesOnPedalChangeTickEvenIfPedalStaysDown() async {
    let sleeper = ControllableSleeper()
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

    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
    )

    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 1440, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        noteSpans: [],
        highlightGuides: [
            makeHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                practiceStepIndex: 0,
                midiNotes: [60],
                noteDurationTicks: 480
            ),
            PianoHighlightGuide(id: 2, kind: .trigger, tick: 1440, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(output.recordedNoteOns.map(\.midi) == [60])
    #expect(output.recordedNoteOffs.contains(60) == false)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(output.recordedNoteOffs.contains(60) == true)
    #expect(viewModel.isSustainPedalDown == true)
}

@Test
@MainActor
func disablingAutoplayStopsAudioAndClearsPendingScheduling() async {
    let sleeper = ControllableSleeper()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope),
        ]
    )
    let output = CapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
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
            PianoHighlightGuide(id: 2, kind: .trigger, tick: 480, durationTicks: nil, practiceStepIndex: 1, activeNotes: [], triggeredNotes: [], releasedMIDINotes: []),
        ]
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    let allNotesOffCountBeforeDisable = output.allNotesOffCount
    viewModel.setAutoplayEnabled(false)
    await settleTaskQueue()

    #expect(output.allNotesOffCount == allNotesOffCountBeforeDisable + 1)
    #expect(await sleeper.cancellationCount() >= 1)
}

@MainActor
private func makePracticeSessionViewModel(
    pressDetectionService: PressDetectionServiceProtocol,
    chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
    sleeper: SleeperProtocol,
    noteAudioPlayer: PracticeNoteAudioPlayerProtocol? = nil,
    noteOutput: PracticeMIDINoteOutputProtocol? = nil
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: pressDetectionService,
        chordAttemptAccumulator: chordAttemptAccumulator,
        sleeper: sleeper,
        noteAudioPlayer: noteAudioPlayer,
        noteOutput: noteOutput ?? CapturingMIDINoteOutput()
    )
}

private func settleTaskQueue(iterations: Int = 4) async {
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

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
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

private final class CapturingPracticeNoteAudioPlayer: PracticeNoteAudioPlayerProtocol {
    private(set) var recordedPlays: [[Int]] = []

    func play(midiNotes: [Int]) throws {
        recordedPlays.append(midiNotes)
    }
}

private final class ThrowingPracticeNoteAudioPlayer: PracticeNoteAudioPlayerProtocol {
    func play(midiNotes _: [Int]) throws {
        throw PracticeAudioError.soundFontMissing(resourceName: "TestSoundFont")
    }
}

private final class CapturingMIDINoteOutput: PracticeMIDINoteOutputProtocol {
    private(set) var recordedNoteOns: [(midi: Int, velocity: UInt8)] = []
    private(set) var recordedNoteOffs: [Int] = []
    private(set) var allNotesOffCount = 0

    func noteOn(midi: Int, velocity: UInt8) throws {
        recordedNoteOns.append((midi: midi, velocity: velocity))
    }

    func noteOff(midi: Int) {
        recordedNoteOffs.append(midi)
    }

    func allNotesOff() {
        allNotesOffCount += 1
    }
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
