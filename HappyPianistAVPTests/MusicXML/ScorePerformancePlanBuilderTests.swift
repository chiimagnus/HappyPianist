@testable import HappyPianistAVP
import Foundation
import Testing

@Test
func timingScheduleRecordsGenericInterpretationProfileForArticulation() {
    let note = MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: 0,
        durationTicks: 480,
        midiNote: 60,
        isRest: false,
        isChord: false,
        staff: 1,
        voice: 1,
        articulations: [.detachedLegato]
    )

    let entry = ScoreTimingScheduleBuilder().build(notes: [note])[0]
    #expect(entry.performedOffTick == 360)
    #expect(entry.releasePolicy == .interpretationProfile)
    #expect(entry.provenance.contains(.interpretationProfile(id: MusicXMLInterpretationProfile.generic.id)))
}

@Test
func timingScheduleKeepsFullTenutoDurationAndRecordsItsProfileRule() {
    let note = MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: 0,
        durationTicks: 480,
        midiNote: 60,
        isRest: false,
        isChord: false,
        staff: 1,
        voice: 1,
        articulations: [.tenuto]
    )

    let entry = ScoreTimingScheduleBuilder().build(notes: [note])[0]
    #expect(entry.performedOnTick == 0)
    #expect(entry.performedOffTick == 480)
    #expect(entry.releasePolicy == .interpretationProfile)
    #expect(entry.provenance.contains(.interpretationProfile(id: MusicXMLInterpretationProfile.generic.id)))
}

@Test
func timingScheduleConnectsSlurReleaseWithoutPedalSemantics() {
    let notes = [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 240,
            midiNote: 60,
            isRest: false,
            isChord: false,
            slurs: [makeSlur(typeToken: "start", numberToken: "2")],
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            midiNote: 62,
            isRest: false,
            isChord: false,
            slurs: [makeSlur(typeToken: "stop", numberToken: "2")],
            staff: 1,
            voice: 1
        ),
    ]

    let schedule = ScoreTimingScheduleBuilder().build(notes: notes)
    #expect(schedule[0].performedOffTick == 480)
    #expect(schedule[0].releasePolicy == .slurLegato)
    #expect(schedule[0].provenance.contains {
        guard case let .performanceNotation(kind, _, profileID) = $0 else { return false }
        return kind == .slur && profileID == MusicXMLInterpretationProfile.generic.id
    })
    #expect(schedule.directives.isEmpty)
}

@Test
func timingScheduleCreatesBreathGapAndCaesuraPauseDirective() {
    let note = MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: 0,
        durationTicks: 480,
        midiNote: 60,
        isRest: false,
        isChord: false,
        staff: 1,
        voice: 1,
        performanceNotations: [
            makePerformanceNotation(kind: .breathMark),
            makePerformanceNotation(kind: .caesura),
        ]
    )

    let schedule = ScoreTimingScheduleBuilder().build(notes: [note])
    #expect(schedule[0].performedOffTick == 420)
    #expect(schedule[0].releasePolicy == .breathGap)
    #expect(schedule.directives == [
        ScoreTimingDirective(
            kind: .caesuraPause,
            tick: 420,
            durationTicks: 240,
            sourceNotationID: nil,
            interpretationProfileID: MusicXMLInterpretationProfile.generic.id
        ),
    ])
}

@Test
func timingSchedulePreservesShortArticulationWhenItConflictsWithSlur() {
    let notes = [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            slurs: [makeSlur(typeToken: "start")],
            staff: 1,
            voice: 1,
            articulations: [.staccato]
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            midiNote: 62,
            isRest: false,
            isChord: false,
            slurs: [makeSlur(typeToken: "stop")],
            staff: 1,
            voice: 1
        ),
    ]

    let first = ScoreTimingScheduleBuilder().build(notes: notes)[0]
    #expect(first.performedOffTick == 240)
    #expect(first.releasePolicy == .interpretationProfile)
    #expect(first.provenance.contains(.approximation(reason: "slur-conflicts-with-short-articulation")))
}

@Test
func performancePlanBuilderPreservesSamePitchVoicesAndPerformedOccurrences() throws {
    let voiceOneID = makeSourceNoteID(sourceOrdinal: 0, voice: 1)
    let voiceTwoID = makeSourceNoteID(sourceOrdinal: 1, voice: 2)
    let notes = [
        makeIdentifiedNote(sourceID: voiceOneID, occurrenceIndex: 0, tick: 0, voice: 1),
        makeIdentifiedNote(sourceID: voiceTwoID, occurrenceIndex: 0, tick: 0, voice: 2),
        makeIdentifiedNote(sourceID: voiceOneID, occurrenceIndex: 1, tick: 480, voice: 1),
    ]

    let plan = try makePerformancePlan(notes: notes)

    #expect(plan.noteEvents.count == 3)
    #expect(Set(plan.noteEvents.map(\.id)).count == 3)
    #expect(plan.noteEvents.map(\.voice) == [1, 2, 1])
    #expect(plan.noteEvents.map(\.performedNoteID.occurrenceIndex) == [0, 0, 1])
}

@Test
func performancePlanBuilderMergesTieChainWithoutLosingContributors() throws {
    let firstID = makeSourceNoteID(sourceOrdinal: 0, voice: 1)
    let secondID = makeSourceNoteID(sourceOrdinal: 1, voice: 1)
    let notes = [
        makeIdentifiedNote(sourceID: firstID, occurrenceIndex: 0, tick: 0, voice: 1, ties: [makeTie(typeToken: "start")]),
        makeIdentifiedNote(sourceID: secondID, occurrenceIndex: 0, tick: 480, voice: 1, ties: [makeTie(typeToken: "stop")]),
    ]

    let plan = try makePerformancePlan(notes: notes)
    let event = try #require(plan.noteEvents.first)

    #expect(plan.noteEvents.count == 1)
    #expect(event.sourceNoteID == firstID)
    #expect(event.contributingSourceNoteIDs == [firstID, secondID])
    #expect(event.writtenOnTick == 0)
    #expect(event.writtenOffTick == 960)
    #expect(event.performedOffTick == 960)
    #expect(plan.approximations.isEmpty)
}

@Test
func performancePlanBuilderReplacesSourceNoteWithGeneratedEvents() throws {
    let sourceID = makeSourceNoteID(sourceOrdinal: 0, voice: 1)
    let note = makeIdentifiedNote(sourceID: sourceID, occurrenceIndex: 0, tick: 0, voice: 1)
    let notationID = MusicXMLPerformanceNotationSourceID(sourceNoteID: sourceID, sourceOrdinal: 0)
    let baseSchedule = ScoreTimingScheduleBuilder().build(notes: [note])
    let schedule = ScoreTimingSchedule(
        entries: baseSchedule.entries,
        generatedNotes: [
            ScoreGeneratedNoteEvent(
                sourceNoteIndices: [0],
                sourceNotationID: notationID,
                notationKind: .trillMark,
                purpose: .ornament,
                ordinal: 0,
                midiNote: 60,
                onTick: 0,
                offTick: 120,
                interpretationProfileID: MusicXMLInterpretationProfile.generic.id
            ),
            ScoreGeneratedNoteEvent(
                sourceNoteIndices: [0],
                sourceNotationID: notationID,
                notationKind: .trillMark,
                purpose: .ornament,
                ordinal: 1,
                midiNote: 62,
                onTick: 120,
                offTick: 240,
                interpretationProfileID: MusicXMLInterpretationProfile.generic.id
            ),
        ],
        notationResolutions: [
            ScorePerformanceNotationResolution(
                sourceNotationID: notationID,
                notationKind: .trillMark,
                sourceNoteIndices: [0],
                replacesSourceNoteIndices: [0],
                status: .generated,
                interpretationProfileID: MusicXMLInterpretationProfile.generic.id
            ),
        ]
    )

    let plan = try makePerformancePlan(notes: [note], timingSchedule: schedule)

    #expect(plan.noteEvents.map(\.purpose) == [.ornament, .ornament])
    #expect(plan.noteEvents.map(\.midiNote) == [60, 62])
    #expect(Set(plan.noteEvents.map(\.id)).count == 2)
}

@Test
func performancePlanBuilderPublishesTimingApproximations() throws {
    let firstID = makeSourceNoteID(sourceOrdinal: 0, voice: 1)
    let secondID = makeSourceNoteID(sourceOrdinal: 1, voice: 1)
    let notes = [
        makeIdentifiedNote(
            sourceID: firstID,
            occurrenceIndex: 0,
            tick: 0,
            voice: 1,
            articulations: [.staccato],
            slurs: [makeSlur(typeToken: "start")]
        ),
        makeIdentifiedNote(
            sourceID: secondID,
            occurrenceIndex: 0,
            tick: 480,
            voice: 1,
            slurs: [makeSlur(typeToken: "stop")]
        ),
    ]

    let plan = try makePerformancePlan(notes: notes)

    #expect(plan.approximations.contains {
        $0.eventIdentity == plan.noteEvents[0].id.description
            && $0.reason == "slur-conflicts-with-short-articulation"
    })
}

private func makePerformancePlan(
    notes: [MusicXMLNoteEvent],
    timingSchedule: ScoreTimingSchedule? = nil
) throws -> ScorePerformancePlan {
    let songID = try #require(UUID(uuidString: "1F1C7688-CFD9-4CD8-8EC5-FD7C80730E18"))
    let logicalInstrument = MusicXMLLogicalInstrument(
        id: "piano:P1",
        memberPartIDs: ["P1"],
        classification: .piano,
        evidence: []
    )
    return ScorePerformancePlanBuilder().build(
        sourceIdentity: ScorePerformanceSourceIdentity(
            songID: songID,
            scoreRevision: "revision",
            logicalInstrumentID: logicalInstrument.id
        ),
        order: MusicXMLOrderSelection(requested: .performed, applied: .performed),
        logicalInstrument: logicalInstrument,
        notes: notes,
        timingSchedule: timingSchedule ?? ScoreTimingScheduleBuilder().build(notes: notes),
        velocityResolver: MusicXMLVelocityResolver(dynamicEvents: []),
        expressivity: MusicXMLExpressivityOptions(),
        handAssignments: [:]
    )
}

private func makeSourceNoteID(sourceOrdinal: Int, voice: Int) -> MusicXMLSourceNoteID {
    MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 1,
        voice: voice,
        sourceOrdinal: sourceOrdinal
    )
}

private func makeIdentifiedNote(
    sourceID: MusicXMLSourceNoteID,
    occurrenceIndex: Int,
    tick: Int,
    voice: Int,
    articulations: Set<MusicXMLArticulation> = [],
    ties: [MusicXMLTie] = [],
    slurs: [MusicXMLSlur] = [],
    performanceNotations: [MusicXMLPerformanceNotation] = []
) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        sourceID: sourceID,
        performedOccurrenceIndex: occurrenceIndex,
        partID: "P1",
        measureNumber: 1,
        tick: tick,
        durationTicks: 480,
        writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4),
        midiNote: 60,
        isRest: false,
        isChord: false,
        ties: ties,
        slurs: slurs,
        staff: 1,
        voice: voice,
        articulations: articulations,
        performanceNotations: performanceNotations
    )
}

private func makeTie(typeToken: String) -> MusicXMLTie {
    MusicXMLTie(
        sourceID: nil,
        sourceElement: .notation,
        typeToken: typeToken,
        numberToken: nil,
        placementToken: nil
    )
}

private func makeSlur(typeToken: String, numberToken: String? = nil) -> MusicXMLSlur {
    MusicXMLSlur(
        sourceID: nil,
        typeToken: typeToken,
        numberToken: numberToken,
        placementToken: nil
    )
}

private func makePerformanceNotation(
    kind: MusicXMLPerformanceNotationKind,
    typeToken: String? = nil,
    numberToken: String? = nil
) -> MusicXMLPerformanceNotation {
    MusicXMLPerformanceNotation(
        sourceID: nil,
        kind: kind,
        rawElementToken: kind.rawValue,
        typeToken: typeToken,
        numberToken: numberToken,
        placementToken: nil,
        textToken: nil,
        attributes: [:]
    )
}
