import Foundation
@testable import LonelyPianistAVP
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
        generation: 1,
        source: .audio
    )

    let consumeTask = Task<DetectedNoteEvent?, Never> {
        for await next in await service.events {
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
    await service.updateExpectedNotes([64], wrongCandidateMIDINotes: [63], generation: 4)
    await service.suppressRecognition(until: now, generation: 4)
    await service.stop()

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
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(fakeService.startCalls.count == 1)
    #expect(fakeService.startCalls.first?.expectedMIDINotes == [60])
}

@Test
@MainActor
func switchingStepUpdatesGenerationAndExpectedNotes() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

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
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

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
            generation: generation - 1,
            source: .audio
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 0)
}

@Test
@MainActor
func matchingAudioEventAdvancesStep() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

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
            generation: generation,
            source: .audio
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func suppressWindowBlocksThenAllowsAdvance() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: fakeService
    )
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
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
            generation: generation,
            source: .audio
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
            generation: generation,
            source: .audio
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func autoplayIsolationBlocksAudioAdvanceUntilAutoplayOff() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    let tempoMap = MusicXMLTempoMap(tempoEvents: [MusicXMLTempoEvent(
        tick: 0,
        quarterBPM: 120,
        scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    )])
    let pedalTimeline = MusicXMLPedalTimeline(events: [])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: [], notes: [])
    let steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 4800, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
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
                    fingeringText: nil
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
                    fingeringText: nil
                ),
            ],
            releasedMIDINotes: []
        ),
    ]
    viewModel.setSteps(
        steps,
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
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
            generation: generation,
            source: .audio
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
            generation: resumedGeneration,
            source: .audio
        )
    )
    await settleTaskQueue()
    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func permissionFailureStatusDoesNotAdvanceAndSetsError() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

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
        fingerTips _: [String: SIMD3<Float>],
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
    ) -> Bool {
        false
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

    func playOneShot(midiNotes: [Int], durationSeconds _: TimeInterval) throws {
        oneShots.append(midiNotes)
    }
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

@Test
@MainActor
func startGuidingPassesPlaybackSuppressDeadlineIntoAudioServiceStart() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: fakeService
    )
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(fakeService.startCalls.first?.suppressUntil != nil)
    #expect(playbackService.oneShots == [[60]])
}

@Test
@MainActor
func microphonePermissionFailureDoesNotBlockPlaybackFallback() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let playbackService = CapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: fakeService
    )
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    fakeService.emitStatus(.permissionDenied)
    await settleTaskQueue()
    viewModel.playCurrentStepSound()

    #expect(viewModel.audioRecognitionErrorMessage == "未授予麦克风权限")
    #expect(playbackService.oneShots.count >= 2)
}

@Test
@MainActor
func disablingAudioRecognitionSettingStopsRunningService() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    UserDefaults.standard.set(false, forKey: "practiceAudioRecognitionEnabled")
    viewModel.refreshAudioRecognitionFromSettings()

    #expect(fakeService.stopCallCount >= 1)
}

@Test
@MainActor
func disablingAudioRecognitionSettingIgnoresQueuedEvents() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeService.startCalls.first?.generation ?? 0

    UserDefaults.standard.set(false, forKey: "practiceAudioRecognitionEnabled")
    viewModel.refreshAudioRecognitionFromSettings()
    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: Date().addingTimeInterval(0.8),
            generation: generation,
            source: .audio
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 0)
}

@Test
@MainActor
func detectorModeSettingRefreshConfiguresServiceWithoutEventTimeUserDefaultsRead() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    UserDefaults.standard.set(
        PracticeAudioRecognitionDetectorMode.harmonicTemplate.rawValue,
        forKey: "practiceStep3AudioRecognitionMode"
    )
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.refreshAudioRecognitionFromSettings()

    #expect(fakeService.configuredDetectorMode == .harmonicTemplate)

    UserDefaults.standard.set(false, forKey: "practiceAudioRecognitionEnabled")
    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: Date().addingTimeInterval(1.0),
            generation: 999,
            source: .audio
        )
    )
    await settleTaskQueue()
    #expect(fakeService.configuredDetectorMode == .harmonicTemplate)
}
