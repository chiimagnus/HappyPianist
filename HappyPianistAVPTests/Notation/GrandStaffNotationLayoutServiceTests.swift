@testable import HappyPianistAVP
import Testing

@Test
func layoutAssignsItemsToTrebleAndBassStaves() {
    let score = notationProjectionScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
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
        projection: .empty,
        measureSpans: measureSpans
    )

    #expect(layout.barlines.map(\.tick) == [0, 480, 960])
}

@Test
func notationProjectionKeepsSourceFactsAndOccurrenceLinksWhileOverlayStaysTransient() throws {
    let score = notationProjectionScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let activeEvent = try #require(plan.noteEvents.first)

    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let overlay = ScoreNotationProjection.Overlay(
        activeEventIDs: [activeEvent.id],
        activeTickRange: 0 ..< 960
    )

    #expect(projection.sourceNotes.count == 2)
    #expect(projection.sourceNotes.map(\.id) == score.notes.compactMap(\.sourceID))
    #expect(projection.sourceNotes.map(\.staff) == score.notes.map { $0.staff ?? 1 })
    #expect(projection.sourceNotes.map(\.voice) == score.notes.map { $0.voice ?? 1 })
    #expect(projection.performedOccurrences.count == 2)
    #expect(projection.performedOccurrences[0].sourceNoteID == projection.sourceNotes[0].id)
    #expect(projection.performedOccurrences[0].performanceEventIDs == [activeEvent.id])
    #expect(overlay.activeEventIDs == [activeEvent.id])
    #expect(overlay.activeTickRange == 0 ..< 960)
    #expect(GrandStaffNotationLayoutService().makeLayout(projection: projection, overlay: overlay).items.count == 1)
}

@Test
func projectionLayoutUsesWrittenDurationAndAccidentalInsteadOfPerformanceOrMidi() throws {
    let score = notationProjectionScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let activeEvent = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)

    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: [activeEvent.id], activeTickRange: nil)
    )
    let flat = try #require(layout.items.first { $0.tick == 0 })
    let sharp = try #require(layout.items.first { $0.tick == 960 })

    #expect(activeEvent.performedOffTick - activeEvent.performedOnTick == 480)
    #expect(flat.durationTicks == 960)
    #expect(flat.noteValue == .half)
    #expect(flat.displayedAccidental?.kind == .flat)
    #expect(flat.isHighlighted)
    #expect(sharp.displayedAccidental?.kind == .sharp)
    #expect(sharp.isHighlighted == false)
    #expect(flat.staffStep == -1)
    #expect(sharp.staffStep == -2)
}

@Test
func projectionResolvesKeyAndMeasureAccidentalStateWithoutLosingPitchTransforms() throws {
    let score = accidentalStateScore()
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(layout.items.map { $0.displayedAccidental?.kind } == [
        nil,
        .natural,
        nil,
        .sharp,
        .natural,
        .unsupported,
    ])
    #expect(projection.sourceNotes.allSatisfy { $0.keySignatureFifths == 1 })
    #expect(projection.sourceNotes.first?.transpose == .init(
        diatonic: -1,
        chromatic: -2,
        octaveChange: 0,
        isDouble: false
    ))
    #expect(projection.sourceNotes.first?.octaveShifts == [
        .init(kind: .up, size: 8, numberToken: "1"),
    ])
    #expect(layout.items.last?.displayedAccidental?.sourceToken == "quarter-sharp")
    #expect(layout.items.last?.displayedAccidental?.alter == 0.5)
}

@Test
func projectionLayoutKeepsEveryWrittenTieContributor() throws {
    let score = notationTieScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let event = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)

    #expect(plan.noteEvents.count == 1)
    #expect(projection.performedOccurrences.count == 2)
    #expect(projection.performedOccurrences.allSatisfy { $0.performanceEventIDs == [event.id] })

    let items = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: [event.id], activeTickRange: nil)
    ).items
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
    #expect(item.staffStep == -1)
}

private func notationProjectionScore() -> MusicXMLScore {
    MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 2,
                voice: 1,
                sourceOrdinal: 0
            ),
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 960,
            writtenPitch: MusicXMLWrittenPitch(step: "D", octave: 4, alter: -1, accidentalToken: "flat"),
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "half"),
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
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
            midiNote: 61,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 2,
            voice: 1
        ),
    ])
}

private func accidentalStateScore() -> MusicXMLScore {
    let pitches: [(measure: Int, tick: Int, pitch: MusicXMLWrittenPitch, midi: Int?)] = [
        (0, 0, .init(step: "F", octave: 4, alter: 1), 66),
        (0, 120, .init(step: "F", octave: 4, accidentalToken: "natural"), 65),
        (0, 240, .init(step: "F", octave: 4), 65),
        (0, 360, .init(step: "F", octave: 4, alter: 1), 66),
        (1, 480, .init(step: "F", octave: 4), 65),
        (1, 600, .init(step: "C", octave: 5, alter: 0.5, accidentalToken: "quarter-sharp"), nil),
    ]
    let notes = pitches.enumerated().map { ordinal, fixture in
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: fixture.measure,
                sourceMeasureNumberToken: String(fixture.measure + 1),
                staff: 1,
                voice: 1,
                sourceOrdinal: ordinal
            ),
            partID: "P1",
            measureNumber: fixture.measure + 1,
            tick: fixture.tick,
            durationTicks: 120,
            writtenPitch: fixture.pitch,
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "16th"),
            midiNote: fixture.midi,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        )
    }
    return MusicXMLScore(
        notes: notes,
        keySignatureEvents: [
            MusicXMLKeySignatureEvent(
                tick: 0,
                fifths: 1,
                modeToken: "major",
                scope: .init(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        transposeEvents: [
            MusicXMLTransposeEvent(
                tick: 0,
                diatonic: -1,
                chromatic: -2,
                octaveChange: 0,
                isDouble: false,
                scope: .init(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        octaveShiftEvents: [
            MusicXMLOctaveShiftEvent(
                tick: 0,
                kind: .up,
                size: 8,
                numberToken: "1",
                scope: .init(partID: "P1", staff: 1, voice: nil)
            ),
        ]
    )
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
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
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
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
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
