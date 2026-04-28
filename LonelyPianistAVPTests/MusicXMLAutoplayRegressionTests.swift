import Foundation
@testable import LonelyPianistAVP
import simd
import Testing


@Test
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
    let output = RegressionCapturingMIDINoteOutput()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: RegressionNoopPressDetectionService(),
        chordAttemptAccumulator: RegressionNoopChordAttemptAccumulator(),
        sleeper: sleeper,
        noteAudioPlayer: nil,
        noteOutput: output
    )

    viewModel.setSteps(
        model.steps,
        tempoMap: model.tempoMap,
        pedalTimeline: model.pedalTimeline,
        fermataTimeline: model.fermataTimeline,
        noteSpans: model.noteSpans,
        highlightGuides: model.guides
    )
    viewModel.setAutoplayEnabled(true)
    viewModel.startGuidingIfReady()
    await settleRegressionTasks()

    let beforeSkip = output.allNotesOffCount
    viewModel.skip()
    await settleRegressionTasks(iterations: 8)

    #expect(output.allNotesOffCount == beforeSkip + 1)
}

private struct AutoplayRegressionModel {
    let score: MusicXMLScore
    let steps: [PracticeStep]
    let noteSpans: [MusicXMLNoteSpan]
    let guides: [PianoHighlightGuide]
    let tempoMap: MusicXMLTempoMap
    let pedalTimeline: MusicXMLPedalTimeline
    let fermataTimeline: MusicXMLFermataTimeline
    let timeline: AutoplayPerformanceTimeline
}

private func makeAutoplayRegressionModel() throws -> AutoplayRegressionModel {
    let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "MusicXMLAutoplayRegression.musicxml")

    let score = try MusicXMLParser().parse(fileURL: fixtureURL)
    let expressivity = MusicXMLRealisticPlaybackDefaults.expressivityOptions
    let buildResult = PracticeStepBuilder().buildSteps(from: score, expressivity: expressivity)
    let wordsSemantics = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: score.wordsEvents,
        tempoEvents: score.tempoEvents
    )
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: score.tempoEvents + wordsSemantics.derivedTempoEvents,
        tempoRamps: wordsSemantics.derivedTempoRamps,
        partID: "P1"
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: score.pedalEvents + wordsSemantics.derivedPedalEvents)
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: score.fermataEvents, notes: score.notes)
    let noteSpans = MusicXMLNoteSpanBuilder().buildSpans(
        from: score.notes,
        performanceTimingEnabled: MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled,
        expressivity: expressivity,
        fermataTimeline: fermataTimeline
    )
    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(
            score: score,
            steps: buildResult.steps,
            noteSpans: noteSpans,
            expressivity: expressivity
        )
    )
    let timeline = AutoplayPerformanceTimeline.build(
        guides: guides,
        steps: buildResult.steps,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        tempoMap: tempoMap
    )

    return AutoplayRegressionModel(
        score: score,
        steps: buildResult.steps,
        noteSpans: noteSpans,
        guides: guides,
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        fermataTimeline: fermataTimeline,
        timeline: timeline
    )
}

private func settleRegressionTasks(iterations: Int = 4) async {
    for _ in 0 ..< iterations {
        await Task.yield()
    }
}

private struct RegressionNoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class RegressionNoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
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

private final class RegressionCapturingMIDINoteOutput: PracticeMIDINoteOutputProtocol {
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
