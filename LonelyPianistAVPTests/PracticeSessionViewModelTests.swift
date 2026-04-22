import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

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
    viewModel.applyCalibration(
        PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0),
        keyRegions: [PianoKeyRegion(midiNote: 60, center: .zero, size: SIMD3<Float>(repeating: 1))]
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
    viewModel.applyCalibration(
        PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0),
        keyRegions: [PianoKeyRegion(midiNote: 60, center: .zero, size: SIMD3<Float>(repeating: 1))]
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
    viewModel.applyCalibration(
        PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0),
        keyRegions: [PianoKeyRegion(midiNote: 60, center: .zero, size: SIMD3<Float>(repeating: 1))]
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
func handleFingerTipPositionsIsNoopWithoutKeyRegions() {
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

    viewModel.applyCalibration(
        PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0),
        keyRegions: [PianoKeyRegion(midiNote: 60, center: .zero, size: SIMD3<Float>(repeating: 1))]
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

@MainActor
private func makePracticeSessionViewModel(
    pressDetectionService: PressDetectionServiceProtocol,
    chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
    sleeper: SleeperProtocol,
    noteAudioPlayer: PracticeNoteAudioPlayerProtocol? = nil
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: pressDetectionService,
        chordAttemptAccumulator: chordAttemptAccumulator,
        sleeper: sleeper,
        noteAudioPlayer: noteAudioPlayer
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
        keyRegions _: [PianoKeyRegion],
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
        keyRegions _: [PianoKeyRegion],
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

    func play(midiNotes: [Int]) {
        recordedPlays.append(midiNotes)
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
