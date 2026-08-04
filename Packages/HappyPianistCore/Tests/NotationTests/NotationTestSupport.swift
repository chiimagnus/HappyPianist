import Foundation
import HappyPianistTestFixtures
@testable import MusicXML
@testable import Practice

func makeTestScorePerformancePlan(
    from score: MusicXMLScore,
    expressivity: MusicXMLExpressivityOptions = MusicXMLExpressivityOptions(),
    handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment] = [:],
    performanceTimingEnabled: Bool = false
) -> ScorePerformancePlan {
    // ponytail: fixtures are single logical pianos; multi-instrument cases must provide an explicit plan.
    let memberPartIDs = Set(score.notes.map(\.partID)).sorted()
    let logicalInstrument = MusicXMLLogicalInstrument(
        id: "test-piano",
        memberPartIDs: memberPartIDs,
        classification: .piano,
        evidence: []
    )
    let timingSchedule = ScoreTimingScheduleBuilder().build(
        notes: score.notes,
        performanceTimingEnabled: performanceTimingEnabled,
        graceEnabled: expressivity.graceEnabled,
        logicalInstruments: [logicalInstrument],
        arpeggiateEnabled: expressivity.arpeggiateEnabled
    )
    let wordsSemantics = expressivity.wordsSemanticsEnabled
        ? MusicXMLWordsSemanticsInterpreter().interpret(
            wordsEvents: score.wordsEvents,
            tempoEvents: score.tempoEvents
        )
        : nil
    return ScorePerformancePlanBuilder().build(
        sourceIdentity: ScorePerformanceSourceIdentity(
            songID: UUID(),
            scoreRevision: "test",
            logicalInstrumentID: logicalInstrument.id
        ),
        order: MusicXMLOrderSelection(requested: .written, applied: .written),
        logicalInstrument: logicalInstrument,
        notes: score.notes,
        timingSchedule: timingSchedule,
        velocityResolver: MusicXMLVelocityResolver(
            dynamicEvents: score.dynamicEvents,
            wedgeEvents: score.wedgeEvents,
            wedgeEnabled: expressivity.wedgeEnabled
        ),
        expressivity: expressivity,
        handAssignments: handAssignments,
        tempoMap: MusicXMLTempoMap(
            tempoEvents: score.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
            tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
            partID: memberPartIDs.first
        ),
        pedalTimeline: MusicXMLPedalTimeline(
            events: score.pedalEvents + (wordsSemantics?.derivedPedalEvents ?? [])
        ),
        tempoAnnotations: wordsSemantics?.tempoAnnotations ?? [],
        fermataTimeline: expressivity.fermataEnabled
            ? MusicXMLFermataTimeline(fermataEvents: score.fermataEvents, notes: score.notes)
            : nil
    )
}

func testFixtureURL(_ name: String) -> URL {
    HappyPianistTestFixtures.url(named: name)
}
