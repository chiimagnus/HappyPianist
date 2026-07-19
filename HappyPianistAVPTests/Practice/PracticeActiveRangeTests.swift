import Foundation
@testable import HappyPianistAVP
import Testing

@Suite("Practice active range")
struct PracticeActiveRangeTests {
    @Test func resolvesSelectedMeasureOccurrencesToOneStepRange() throws {
        let steps = makeSteps()
        let spans = makeSpans()
        let passage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))

        let activeRange = try PracticeMeasureIndex(steps: steps, measureSpans: spans).resolve(passage)

        #expect(activeRange.occurrenceRange == 1 ..< 3)
        #expect(activeRange.stepRange == 1 ..< 3)
        #expect(activeRange.tickRange == 480 ..< 1440)
        #expect(activeRange.measureSpans.map(\.measureNumber) == [2, 3])
    }

    @Test func navigatorNeverAdvancesOutsidePassage() throws {
        let steps = makeSteps()
        let spans = makeSpans()
        let passage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))
        let activeRange = try PracticeMeasureIndex(steps: steps, measureSpans: spans).resolve(passage)
        let navigator = PracticeStepNavigator()

        let started = navigator.restart(steps: steps, activeRange: activeRange)
        #expect(started.currentStepIndex == 1)
        #expect(navigator.advance(steps: steps, currentStepIndex: 1, activeRange: activeRange).currentStepIndex == 2)
        #expect(navigator.advance(steps: steps, currentStepIndex: 2, activeRange: activeRange).state == .completed)
        #expect(navigator.move(to: 0, steps: steps, activeRange: activeRange).state == .completed)
    }

    @Test @MainActor func autoplayTimelineContainsOnlySelectedPassageEvents() throws {
        let steps = makeSteps()
        let spans = makeSpans()
        let passage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))
        let activeRange = try PracticeMeasureIndex(steps: steps, measureSpans: spans).resolve(passage)
        let guides = steps.enumerated().map { index, step in
            PianoHighlightGuide(
                id: index,
                kind: .trigger,
                tick: step.tick,
                durationTicks: 240,
                practiceStepIndex: index,
                activeNotes: [],
                triggeredNotes: [
                    PianoHighlightNote(
                        occurrenceID: "active-range-\(index)",
                        midiNote: 60 + index,
                        staff: 1,
                        voice: 1,
                        velocity: 80,
                        onTick: step.tick,
                        offTick: step.tick + 240,
                        fingerings: [],
                        handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
                    ),
                ],
                releasedMIDINotes: []
            )
        }
        let timeline = AutoplayPerformanceTimeline.build(
            plan: makeTestScorePerformancePlan(
                notes: steps.enumerated().map { index, step in
                    TestScorePerformanceNote(
                        midiNote: 60 + index,
                        velocity: 80,
                        onTick: step.tick,
                        offTick: step.tick + 240,
                        handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
                    )
                }
            ),
            guideProjection: guides,
            stepProjection: steps,
            tempoMap: MusicXMLTempoMap(tempoEvents: []),
            practiceHandMode: .both,
            activeRange: activeRange
        )

        #expect(timeline.events.allSatisfy { $0.tick >= 480 && $0.tick <= 1440 })
        let stepIndices = timeline.events.compactMap { event -> Int? in
            guard case let .advanceStep(index) = event.kind else { return nil }
            return index
        }
        #expect(stepIndices == [1, 2])
    }

    private func makeSteps() -> [PracticeStep] {
        [0, 480, 960, 1440].enumerated().map { index, tick in
            PracticeStep(tick: tick, notes: [PracticeStepNote(midiNote: 60 + index, staff: 1, handAssignment: .unknown)])
        }
    }

    private func makeSpans() -> [MusicXMLMeasureSpan] {
        (0 ..< 4).map { index in
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: index + 1,
                sourceMeasureIndex: index,
                sourceMeasureNumberToken: "\(index + 1)",
                occurrenceIndex: index,
                startTick: index * 480,
                endTick: (index + 1) * 480
            )
        }
    }
}
