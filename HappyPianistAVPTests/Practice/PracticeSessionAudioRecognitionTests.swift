import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
func fakeAudioRecognitionServiceEmitsEventToConsumer() async {
    let service = FakePracticeAudioRecognitionService()
    let event = makeTargetAudioEvidence(
        midiNote: 60,
        confidence: 0.9,
        onsetScore: 0.8,
        isOnset: true,
        timestamp: .init(seconds: 1000),
        generation: 1
    )

    let stream = service.targetEvidence
    let consumeTask = Task<TargetAudioEvidence?, Never> {
        for await next in stream {
            return next
        }
        return nil
    }

    service.emitEvidence(event)
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

    fakeService.emitEvidence(
        makeTargetAudioEvidence(
            midiNote: 60,
            confidence: 0.9,
            onsetScore: 0.8,
            isOnset: true,
            timestamp: .init(seconds: 1),
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

    fakeService.emitEvidence(
        makeTargetAudioEvidence(
            midiNote: 60,
            confidence: 0.92,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: .init(seconds: 1),
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
    fakeService.emitEvidence(
        makeTargetAudioEvidence(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: .init(seconds: 1),
            generation: generation
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 0)

    viewModel.setAutoplayEnabled(false)
    await settleTaskQueue()
    let resumedGeneration = fakeService.startCalls.last?.generation ?? generation
    fakeService.emitEvidence(
        makeTargetAudioEvidence(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: .init(seconds: 2),
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

private final class CapturingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var oneShots: [[Int]] = []

    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {
        oneShots.append(commands.compactMap {
            guard case let .noteOn(midi, _) = $0.kind else { return nil }
            return midi
        })
    }

    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

@Test
@MainActor
func startGuidingPassesPlaybackSuppressDeadlineIntoAudioServiceStart() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
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
    await settleTaskQueue()

    #expect(viewModel.audioRecognitionErrorMessage == "未授予麦克风权限")
    #expect(playbackService.oneShots.count >= 2)
}
