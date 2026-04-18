import Foundation
import Testing
import simd
@testable import LonelyPianistAVP

@Test
@MainActor
func markCorrectSchedulesFeedbackResetWithExpectedDuration() async {
    let sleeper = ControllableSleeper()
    let viewModel = makePracticeSessionViewModel(sleeper: sleeper)

    viewModel.markCorrect()
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
    let viewModel = makePracticeSessionViewModel(sleeper: sleeper)

    viewModel.markCorrect()
    await settleTaskQueue()
    viewModel.markCorrect()
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
    let viewModel = makePracticeSessionViewModel(sleeper: sleeper)

    viewModel.markCorrect()
    await settleTaskQueue()
    #expect(viewModel.feedbackState == .correct)

    await sleeper.resumeOldestPending()
    await settleTaskQueue()

    #expect(viewModel.feedbackState == .none)
}

@MainActor
private func makePracticeSessionViewModel(sleeper: SleeperProtocol) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: sleeper
    )
}

private func settleTaskQueue(iterations: Int = 4) async {
    for _ in 0..<iterations {
        await Task.yield()
    }
}

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips: [String : SIMD3<Float>],
        keyRegions: [PianoKeyRegion],
        at timestamp: Date
    ) -> Set<Int> {
        []
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool {
        false
    }

    func reset() {}
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
