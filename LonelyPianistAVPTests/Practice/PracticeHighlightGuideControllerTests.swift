import Foundation
@testable import LonelyPianistAVP
import Testing

private actor ControllableSleeper: SleeperProtocol {
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private var recorded: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recorded.append(duration)
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func recordedDurations() -> [Duration] {
        recorded
    }

    func resumeOldest() {
        guard continuations.isEmpty == false else { return }
        continuations.removeFirst().resume()
    }
}

@Test
@MainActor
func transitionGuideSchedulesDelayedSwitchToTrigger() async {
    let sleeper = ControllableSleeper()
    let store = PracticeSessionStateStore()
    store.autoplayState = .off
    store.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 100, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]

    store.highlightGuides = [
        PianoHighlightGuide(
            id: 0,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 1,
            kind: .release,
            tick: 50,
            durationTicks: nil,
            practiceStepIndex: nil,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 100,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let controller = PracticeHighlightGuideController(sleeper: sleeper, stateStore: store)
    controller.updateHighlightGuideAfterStepAdvance(previousTick: 0, nextStepIndex: 1)

    #expect(store.currentHighlightGuideIndex == 1)
    for _ in 0 ..< 20 {
        if await sleeper.recordedDurations().contains(.seconds(0.12)) {
            break
        }
        await Task.yield()
    }
    #expect(await sleeper.recordedDurations().contains(.seconds(0.12)))

    await sleeper.resumeOldest()
    for _ in 0 ..< 20 {
        await Task.yield()
    }

    #expect(store.currentHighlightGuideIndex == 2)
}

@Test
@MainActor
func shutdownCancelsPendingTransitionTask() async {
    let sleeper = ControllableSleeper()
    let store = PracticeSessionStateStore()
    store.autoplayState = .off
    store.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 100, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]

    store.highlightGuides = [
        PianoHighlightGuide(
            id: 0,
            kind: .trigger,
            tick: 0,
            durationTicks: nil,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 1,
            kind: .gap,
            tick: 50,
            durationTicks: nil,
            practiceStepIndex: nil,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
        PianoHighlightGuide(
            id: 2,
            kind: .trigger,
            tick: 100,
            durationTicks: nil,
            practiceStepIndex: 1,
            activeNotes: [],
            triggeredNotes: [],
            releasedMIDINotes: []
        ),
    ]

    let controller = PracticeHighlightGuideController(sleeper: sleeper, stateStore: store)
    controller.updateHighlightGuideAfterStepAdvance(previousTick: 0, nextStepIndex: 1)
    #expect(store.currentHighlightGuideIndex == 1)

    controller.shutdown()
    await sleeper.resumeOldest()
    await Task.yield()

    #expect(store.currentHighlightGuideIndex == 1)
}
