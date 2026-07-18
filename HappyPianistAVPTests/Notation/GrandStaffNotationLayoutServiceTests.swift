@testable import HappyPianistAVP
import Testing

@Test
func layoutAssignsItemsToTrebleAndBassStaves() {
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: 480,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [
                PianoHighlightNote(
                    occurrenceID: "n1",
                    midiNote: 60,
                    staff: 1,
                    voice: 1,
                    velocity: 96,
                    onTick: 0,
                    offTick: 480,
                    fingeringText: nil,
                    handAssignment: .unknown
                ),
                PianoHighlightNote(
                    occurrenceID: "n2",
                    midiNote: 48,
                    staff: 2,
                    voice: 1,
                    velocity: 96,
                    onTick: 0,
                    offTick: 480,
                    fingeringText: nil,
                    handAssignment: .unknown
                ),
            ],
            releasedMIDINotes: []
        ),
    ]

    let layout = GrandStaffNotationLayoutService().makeLayout(
        guides: guides,
        currentGuide: guides[0]
    )

    #expect(layout.items.count == 2)
    #expect(Set(layout.items.map(\.staffNumber)) == [1, 2])
}

@Test
func layoutEmitsBarlinesForMeasureSpansStartAndEndTicks() {
    let measureSpans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 2, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]

    let layout = GrandStaffNotationLayoutService().makeLayout(
        guides: [
            PianoHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                durationTicks: 480,
                practiceStepIndex: 0,
                activeNotes: [],
                triggeredNotes: [],
                releasedMIDINotes: []
            ),
        ],
        currentGuide: nil,
        measureSpans: measureSpans
    )

    #expect(layout.barlines.map(\.tick) == [0, 480, 960])
}

@Test
func notationProjectionKeepsSourceFactsOccurrenceLinksAndActiveState() throws {
    let score = notationProjectionScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let activeEvent = try #require(plan.noteEvents.first)

    let projection = ScoreNotationProjection(
        plan: plan,
        sourceScore: score,
        activeState: .init(occurrenceIDs: [activeEvent.id])
    )

    #expect(projection.sourceNotes.count == 2)
    #expect(projection.performedOccurrences.count == 2)
    #expect(projection.performedOccurrences[0].primarySourceNoteID == projection.sourceNotes[0].id)
    #expect(projection.performedOccurrences[0].contributingSourceNoteIDs == [projection.sourceNotes[0].id])
    #expect(projection.activeState.occurrenceIDs == [activeEvent.id])
}

@Test
func projectionLayoutUsesWrittenDurationAndAccidentalInsteadOfPerformanceOrMidi() throws {
    let score = notationProjectionScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let activeEvent = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(
        plan: plan,
        sourceScore: score,
        activeState: .init(occurrenceIDs: [activeEvent.id])
    )

    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)
    let flat = try #require(layout.items.first { $0.midiNote == 61 })
    let sharp = try #require(layout.items.first { $0.midiNote == 60 })

    #expect(activeEvent.performedOffTick - activeEvent.performedOnTick == 480)
    #expect(flat.durationTicks == 960)
    #expect(flat.noteValue == .half)
    #expect(flat.showsSharpAccidental == false)
    #expect(flat.isHighlighted)
    #expect(sharp.showsSharpAccidental)
    #expect(sharp.isHighlighted == false)
}

private func notationProjectionScore() -> MusicXMLScore {
    MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 1,
                voice: 1,
                sourceOrdinal: 0
            ),
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 960,
            writtenPitch: MusicXMLWrittenPitch(step: "D", octave: 4, alter: -1, accidentalToken: "flat"),
            midiNote: 61,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1,
            articulations: [.staccato]
        ),
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 1,
                voice: 1,
                sourceOrdinal: 1
            ),
            partID: "P1",
            measureNumber: 1,
            tick: 960,
            durationTicks: 480,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4, alter: 1, accidentalToken: "sharp"),
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
    ])
}
