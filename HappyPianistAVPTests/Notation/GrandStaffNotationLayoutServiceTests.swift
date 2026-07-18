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
    #expect(projection.performedOccurrences[0].sourceNoteID == projection.sourceNotes[0].id)
    #expect(projection.performedOccurrences[0].performanceEventIDs == [activeEvent.id])
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

@Test
func projectionLayoutKeepsEveryWrittenTieContributor() throws {
    let score = notationTieScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let event = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(
        plan: plan,
        sourceScore: score,
        activeState: .init(occurrenceIDs: [event.id])
    )

    #expect(plan.noteEvents.count == 1)
    #expect(projection.performedOccurrences.count == 2)
    #expect(projection.performedOccurrences.allSatisfy { $0.performanceEventIDs == [event.id] })

    let items = GrandStaffNotationLayoutService().makeLayout(projection: projection).items
    #expect(items.map(\.tick) == [0, 480])
    #expect(items.map(\.tieStart) == [true, false])
    #expect(items.map(\.tieStop) == [false, true])
    #expect(items.allSatisfy { $0.isHighlighted })
}

@Test
func projectionDeduplicatesGeneratedPerformanceEventsForOneWrittenOccurrence() throws {
    let score = MusicXMLScore(notes: [notationProjectionScore().notes[0]])
    let basePlan = makeTestScorePerformancePlan(from: score)
    let sourceEvent = try #require(basePlan.noteEvents.first)
    let generatedEvents = [0, 1].map { ordinal in
        ScorePerformanceNoteEvent(
            id: ScorePerformanceNoteEventID(
                performedNoteID: sourceEvent.performedNoteID,
                generatedOrdinal: ordinal
            ),
            sourceNoteID: sourceEvent.sourceNoteID,
            performedNoteID: sourceEvent.performedNoteID,
            contributingSourceNoteIDs: sourceEvent.contributingSourceNoteIDs,
            contributingPerformedNoteIDs: sourceEvent.contributingPerformedNoteIDs,
            purpose: .ornament,
            writtenOnTick: sourceEvent.writtenOnTick,
            writtenOffTick: sourceEvent.writtenOffTick,
            performedOnTick: ordinal * 120,
            performedOffTick: ordinal * 120 + 120,
            writtenPitch: sourceEvent.writtenPitch,
            midiNote: sourceEvent.midiNote + ordinal,
            velocityResolution: sourceEvent.velocityResolution,
            staff: sourceEvent.staff,
            voice: sourceEvent.voice,
            handAssignment: sourceEvent.handAssignment,
            fingeringText: sourceEvent.fingeringText,
            timingProvenance: sourceEvent.timingProvenance
        )
    }
    let plan = ScorePerformancePlan(
        id: basePlan.id,
        sourceScoreIdentity: basePlan.sourceScoreIdentity,
        order: basePlan.order,
        resolution: basePlan.resolution,
        noteEvents: generatedEvents,
        tempoEvents: basePlan.tempoEvents,
        controllerEvents: basePlan.controllerEvents,
        annotations: basePlan.annotations,
        approximations: basePlan.approximations
    )

    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let occurrence = try #require(projection.performedOccurrences.first)
    let item = try #require(GrandStaffNotationLayoutService().makeLayout(projection: projection).items.first)

    #expect(projection.performedOccurrences.count == 1)
    #expect(occurrence.performanceEventIDs == generatedEvents.map(\.id))
    #expect(item.midiNote == score.notes[0].midiNote)
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

private func notationTieScore() -> MusicXMLScore {
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
            durationTicks: 480,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4),
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: true,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 1,
                sourceMeasureNumberToken: "2",
                staff: 1,
                voice: 1,
                sourceOrdinal: 1
            ),
            partID: "P1",
            measureNumber: 2,
            tick: 480,
            durationTicks: 480,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4),
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: true,
            staff: 1,
            voice: 1
        ),
    ])
}
