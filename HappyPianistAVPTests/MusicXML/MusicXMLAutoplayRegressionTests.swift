import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
@MainActor
func realScoreAutoplayTimelineKeepsNoteOnAndGuideAdvanceSynchronized() throws {
    let model = try makeAutoplayRegressionModel()
    let firstTrigger = try #require(model.guides.first { $0.kind == .trigger })
    let firstTriggeredNote = try #require(firstTrigger.triggeredNotes.first)

    let firstNoteOn = try #require(model.timeline.events.first { event in
        if case let .noteOn(midi, _) = event.kind {
            return midi == firstTriggeredNote.midiNote
        }
        return false
    })
    let firstGuideAdvance = try #require(model.timeline.events.first { event in
        if case let .advanceGuide(_, guideID) = event.kind {
            return guideID == firstTrigger.id
        }
        return false
    })

    #expect(firstNoteOn.tick == firstTriggeredNote.onTick)
    #expect(firstNoteOn.tick == firstTrigger.tick)
    #expect(firstGuideAdvance.tick == firstNoteOn.tick)
    #expect(model.score.wordsEvents.contains { $0.text == "rit." })
    #expect(model.score.notes.contains { $0.attackTicks != nil && $0.releaseTicks != nil })
    #expect(model.score.notes.contains { $0.articulations.contains(.staccato) })
    #expect(model.score.fermataEvents.isEmpty == false)
}

@Test
@MainActor
func realScoreAutoplaySkipCancelsPendingEventsWithAllNotesOff() async throws {
    let model = try makeAutoplayRegressionModel()
    let sleeper = RegressionControllableSleeper()
    let playbackService = RegressionCapturingSequencerPlaybackService()
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: RegressionNoopChordAttemptAccumulator(),
        sleeper: sleeper,
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformancePlan(
        model.plan,
        sourceScore: model.score,
        highlightGuides: model.guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await waitForRegressionCondition("initial autoplay reset") {
        playbackService.stopCount > 0
    }

    let beforeSkip = playbackService.stopCount
    viewModel.skip()
    await waitForRegressionCondition("skip reset") {
        playbackService.stopCount == beforeSkip + 1
    }

    #expect(playbackService.stopCount == beforeSkip + 1)
}

private final class RegressionCapturingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var stopCount = 0

    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {
        stopCount += 1
    }

    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

private struct AutoplayRegressionModel {
    let score: MusicXMLScore
    let plan: ScorePerformancePlan
    let guides: [PianoHighlightGuide]
    let timeline: AutoplayPerformanceTimeline
}

@MainActor
private func makeAutoplayRegressionModel() throws -> AutoplayRegressionModel {
    let fixture = try PianoPerformanceFixtureLoader().fixture(id: "musicxml-autoplay-regression")

    let score = try MusicXMLParser().parse(fileURL: fixture.url)
    let expressivity = MusicXMLRealisticPlaybackDefaults.expressivityOptions
    let plan = makeTestScorePerformancePlan(from: score, expressivity: expressivity)
    let buildResult = PracticeStepBuilder().buildSteps(from: plan)
    let wordsSemantics = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: score.wordsEvents,
        tempoEvents: score.tempoEvents
    )
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: score.tempoEvents + wordsSemantics.derivedTempoEvents,
        tempoRamps: wordsSemantics.derivedTempoRamps,
        partID: "P1"
    )
    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(
            plan: plan,
            sourceScore: score
        )
    )
    let timeline = AutoplayPerformanceTimeline.build(
        plan: plan,
        guideProjection: guides,
        stepProjection: buildResult.steps,
        tempoMap: tempoMap,
        practiceHandMode: .both
    )

    return AutoplayRegressionModel(
        score: score,
        plan: plan,
        guides: guides,
        timeline: timeline
    )
}

private func settleRegressionTasks(iterations: Int = 4) async {
    for _ in 0 ..< iterations {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private func waitForRegressionCondition(
    _ description: String,
    condition: () -> Bool
) async {
    for _ in 0 ..< 240 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition(), "Timed out waiting for: \(description)")
}

private final class RegressionNoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

private actor RegressionControllableSleeper: SleeperProtocol {
    private var requests: [UUID] = []
    private var continuationsByID: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var cancelledRequestIDs: Set<UUID> = []

    func sleep(for _: Duration) async throws {
        let requestID = UUID()
        requests.append(requestID)

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

    func cancellationCount() -> Int {
        cancelledRequestIDs.count
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
