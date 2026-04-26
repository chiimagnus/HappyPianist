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
        timestamp: Date(timeIntervalSince1970: 1_000),
        generation: 1,
        source: .audio
    )

    let consumeTask = Task<DetectedNoteEvent?, Never> {
        for await next in service.events {
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
    let now = Date(timeIntervalSince1970: 2_000)
    try await service.start(expectedMIDINotes: [60], wrongCandidateMIDINotes: [61, 62], generation: 3)
    service.updateExpectedNotes([64], wrongCandidateMIDINotes: [63], generation: 4)
    service.suppressRecognition(until: now, generation: 4)
    service.stop()

    #expect(service.startCalls == [.init(expectedMIDINotes: [60], wrongCandidateMIDINotes: [61, 62], generation: 3)])
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
    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
    ])

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
    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
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
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = makeViewModel(audioRecognitionService: fakeService)
    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
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
    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
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
            timestamp: .now,
            generation: generation,
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
    viewModel.setSteps([
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
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
    PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        noteAudioPlayer: nil,
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
