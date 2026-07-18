import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
func fakeAudioRecognitionServiceEmitsEventToConsumer() async {
    let service = FakePracticeAudioRecognitionService()
    let event = DetectedNoteEvent(
        midiNote: 60,
        confidence: 0.9,
        onsetScore: 0.8,
        isOnset: true,
        timestamp: Date(timeIntervalSince1970: 1000),
        generation: 1
    )

    let stream = service.events
    let consumeTask = Task<DetectedNoteEvent?, Never> {
        for await next in stream {
            return next
        }
        return nil
    }

    service.emitEvent(event)
    let received = await consumeTask.value

    #expect(received == event)
}

@Test
func fakeAudioRecognitionServiceRecordsLifecycleCalls() async throws {
    let service = FakePracticeAudioRecognitionService()
    let now = Date(timeIntervalSince1970: 2000)
    try await service.start(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [61, 62],
        generation: 3,
        suppressUntil: nil
    )
    service.updateExpectedNotes([64], wrongCandidateMIDINotes: [63], generation: 4)
    service.suppressRecognition(until: now, generation: 4)
    service.stop()

    #expect(service.startCalls == [.init(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [61, 62],
        generation: 3,
        suppressUntil: nil
    )])
    #expect(service.updateCalls == [.init(expectedMIDINotes: [64], wrongCandidateMIDINotes: [63], generation: 4)])
    #expect(service.suppressCalls == [.init(until: now, generation: 4)])
    #expect(service.stopCallCount == 1)
}

@Test
@MainActor
func guidingStartsAudioRecognitionService() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(fakeService.startCalls.count == 1)
    #expect(fakeService.startCalls.first?.expectedMIDINotes == [60])
}

@Test
@MainActor
func switchingStepUpdatesGenerationAndExpectedNotes() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 64, onTick: 10),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let firstGeneration = fakeService.startCalls.first?.generation

    viewModel.skip()
    await settleTaskQueue()

    #expect(fakeService.updateCalls.last?.expectedMIDINotes == [64])
    #expect((fakeService.updateCalls.last?.generation ?? 0) > (firstGeneration ?? 0))
}

@Test
@MainActor
func staleGenerationEventDoesNotAdvanceStep() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 64, onTick: 10),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeService.startCalls.first?.generation ?? 0

    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.9,
            onsetScore: 0.8,
            isOnset: true,
            timestamp: .now,
            generation: generation - 1
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 0)
}

@Test
@MainActor
func matchingAudioEventAdvancesStep() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 64, onTick: 10),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeService.startCalls.first?.generation ?? 0

    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.92,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: Date().addingTimeInterval(0.8),
            generation: generation
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func suppressWindowBlocksThenAllowsAdvance() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: fakeService
    )
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 64, onTick: 10),
        ])
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    guard let startCall = fakeService.startCalls.first else {
        #expect(Bool(false), "Expected audio recognition to start")
        return
    }
    guard let suppressUntil = startCall.suppressUntil else {
        #expect(Bool(false), "Expected suppressUntil to be set")
        return
    }
    let generation = startCall.generation

    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.9,
            onsetScore: 0.8,
            isOnset: true,
            timestamp: suppressUntil.addingTimeInterval(-0.1),
            generation: generation
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 0)

    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.9,
            onsetScore: 0.8,
            isOnset: true,
            timestamp: suppressUntil.addingTimeInterval(0.2),
            generation: generation
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func autoplayIsolationBlocksAudioAdvanceUntilAutoplayOff() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    let tempoMap = MusicXMLTempoMap(tempoEvents: [MusicXMLTempoEvent(
        tick: 0,
        quarterBPM: 120,
        scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    )])
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let notes = [
        TestScorePerformanceNote(midiNote: 60, onTick: 0),
        TestScorePerformanceNote(midiNote: 64, onTick: 4800),
    ]
    let guides = [
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
                    staff: nil,
                    voice: nil,
                    velocity: 96,
                    onTick: 0,
                    offTick: 1,
                    fingeringText: nil,
                    handAssignment: .unknown
                ),
            ],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 4800,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [
                PianoHighlightNote(
                    occurrenceID: "t4800-64",
                    midiNote: 64,
                    staff: nil,
                    voice: nil,
                    velocity: 96,
                    onTick: 4800,
                    offTick: 4801,
                    fingeringText: nil,
                    handAssignment: .unknown
                ),
            ],
            releasedMIDINotes: []
        ),
    ]
    viewModel.installTestPerformanceNotes(
        notes,
        tempoEvents: makeTestScorePerformanceTempoEvents(from: tempoMap),
        controllerEvents: makeTestScorePerformanceControllerEvents(from: pedalTimeline),
        highlightGuides: guides
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeService.startCalls.first?.generation ?? 0

    viewModel.setAutoplayEnabled(true)
    await settleTaskQueue()
    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: Date().addingTimeInterval(0.8),
            generation: generation
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 0)

    viewModel.setAutoplayEnabled(false)
    await settleTaskQueue()
    let resumedGeneration = fakeService.startCalls.last?.generation ?? generation
    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: Date().addingTimeInterval(1.6),
            generation: resumedGeneration
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func permissionFailureStatusDoesNotAdvanceAndSetsError() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 64, onTick: 10),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    fakeService.emitStatus(.permissionDenied)
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 0)
    #expect(viewModel.audioErrorMessage?.isEmpty == false)
}

@MainActor
private func makeViewModel(
    audioRecognitionService: PracticeAudioRecognitionServiceProtocol
) -> PracticeSessionViewModel {
    let playbackService = CapturingSequencerPlaybackService()
    return PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: audioRecognitionService
    )
}

private func settleTaskQueue(iterations: Int = 4) async {
    for _ in 0 ..< iterations {
        await Task.yield()
    }
}

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

private final class CapturingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var oneShots: [[Int]] = []

    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(noteOns: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {
        oneShots.append(noteOns.map(\.midiNote))
    }

    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

@Test
@MainActor
func startGuidingPassesPlaybackSuppressDeadlineIntoAudioServiceStart() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: fakeService
    )
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(fakeService.startCalls.first?.suppressUntil != nil)
    #expect(playbackService.oneShots == [[60]])
}

@Test
@MainActor
func microphonePermissionFailureDoesNotBlockPlaybackFallback() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: fakeService
    )
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    fakeService.emitStatus(.permissionDenied)
    await settleTaskQueue()
    viewModel.previewCurrentStepPitches()

    #expect(viewModel.audioRecognitionErrorMessage == "未授予麦克风权限")
    #expect(playbackService.oneShots.count >= 2)
}
