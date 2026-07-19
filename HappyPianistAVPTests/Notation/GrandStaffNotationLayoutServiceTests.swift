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
    #expect(sharp.staffStep == 10)
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
    #expect(projection.sourceNotes.allSatisfy { $0.keySignature?.fifths == 1 })
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

    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: [event.id], activeTickRange: nil)
    )
    let items = layout.items
    #expect(items.map(\.tick) == [0, 480])
    #expect(items.allSatisfy { $0.isHighlighted })
    let tie = try #require(layout.ties.first)
    #expect(layout.ties.count == 1)
    #expect(tie.startOccurrenceID == items[0].occurrenceID)
    #expect(tie.endOccurrenceID == items[1].occurrenceID)
    #expect(tie.continuesFromPrevious == false)
    #expect(tie.continuesToNext == false)
}

@Test
func layoutKeepsTieContinuationAcrossActiveRangeAndViewportBoundary() throws {
    let score = notationTieScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        ),
        overlay: .init(activeEventIDs: [], activeTickRange: 240 ..< 960),
        halfWindowTicks: 120,
        scrollTick: 480
    )

    let tie = try #require(layout.ties.first)
    #expect(tie.continuesFromPrevious)
    #expect(tie.continuesToNext == false)
    #expect(tie.startOccurrenceID == nil)
    #expect(tie.endOccurrenceID == layout.items.first?.occurrenceID)
}

@Test
func projectionAndLayoutKeepVisibleRestsSameNumberSlursAndNestedTuplets() throws {
    let score = notationRestAndSpannerScore()
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(projection.sourceNotes.filter(\.isRest).map(\.isPrintObjectVisible) == [true, false])
    let rest = try #require(layout.rests.first)
    #expect(layout.rests.count == 1)
    #expect(rest.staffNumber == 2)
    #expect(rest.voice == 2)
    #expect(rest.noteValue == .quarter)
    #expect(rest.dotCount == 1)

    #expect(layout.slurs.map(\.numberToken) == ["2", "2"])
    #expect(layout.slurs.map(\.placementToken) == ["above", "below"])
    #expect(layout.slurs.allSatisfy { !$0.continuesFromPrevious && !$0.continuesToNext })
    #expect(layout.tuplets.map(\.numberToken) == ["1", "2"])
    #expect(layout.tuplets.map(\.displayNumber) == [3, 3])
    #expect(layout.tuplets.map(\.bracketToken) == ["yes", "no"])
    #expect(layout.tuplets.map(\.nestingLevel) == [0, 1])
    #expect(layout.tuplets.allSatisfy { $0.startOccurrenceID != nil && $0.endOccurrenceID != nil })
}

@Test
func sourceBeamValuesProducePrimarySecondaryAndHookSegments() throws {
    let score = mixedSourceBeamScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    let beam = try #require(layout.beams.first)
    let firstChordID = try #require(beam.chordIDs.first)
    let lastChordID = try #require(beam.chordIDs.last)
    #expect(layout.beams.count == 1)
    #expect(beam.chordIDs.count == 4)
    #expect(beam.segments.contains {
        $0.level == 1 && $0.startChordID == firstChordID && $0.endChordID == lastChordID && $0.hookDirection == nil
    })
    #expect(beam.segments.contains {
        $0.level == 2 && $0.startChordID == beam.chordIDs[0] && $0.endChordID == beam.chordIDs[0] && $0.hookDirection == .forward
    })
    #expect(beam.segments.contains {
        $0.level == 2 && $0.startChordID == beam.chordIDs[2] && $0.endChordID == beam.chordIDs[3] && $0.hookDirection == nil
    })
}

@Test
func meterFallbackStopsAtBeatAndRestBoundaries() throws {
    let score = fallbackBeamRestScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    let beam = try #require(layout.beams.first)
    let chordsByID = Dictionary(uniqueKeysWithValues: layout.chords.map { ($0.id, $0) })
    #expect(layout.beams.count == 1)
    #expect(beam.chordIDs.compactMap { chordsByID[$0]?.tick } == [480, 720])
    #expect(layout.items.filter { $0.tick < 480 }.allSatisfy { $0.beamID == nil })
}

@Test
func spannersKeepNestedLevelsAndViewportContinuationSeparateByKind() throws {
    let score = notationRestAndSpannerScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        ),
        halfWindowTicks: 60,
        scrollTick: 180
    )

    #expect(layout.ties.isEmpty)
    #expect(layout.slurs.allSatisfy { $0.id.contains("slur") })
    #expect(layout.tuplets.allSatisfy { $0.id.contains("tuplet") })
    #expect(layout.tuplets.contains { $0.continuesFromPrevious || $0.continuesToNext })
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
            fingerings: sourceEvent.fingerings,
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
                staff: 1,
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
            staff: 1,
            voice: 1,
            articulations: [.staccato]
        ),
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 2,
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
            staff: 2,
            voice: 1
        ),
    ])
}

private func mixedSourceBeamScore() -> MusicXMLScore {
    let fixtures: [(tick: Int, duration: Int, type: String, beams: [MusicXMLBeam])] = [
        (0, 120, "16th", [
            .init(numberToken: "1", value: .begin, repeaterToken: nil, fanToken: nil),
            .init(numberToken: "2", value: .forwardHook, repeaterToken: nil, fanToken: nil),
        ]),
        (120, 240, "eighth", [
            .init(numberToken: "1", value: .continue, repeaterToken: nil, fanToken: nil),
        ]),
        (360, 120, "16th", [
            .init(numberToken: "1", value: .continue, repeaterToken: nil, fanToken: nil),
            .init(numberToken: "2", value: .begin, repeaterToken: nil, fanToken: nil),
        ]),
        (480, 120, "16th", [
            .init(numberToken: "1", value: .end, repeaterToken: nil, fanToken: nil),
            .init(numberToken: "2", value: .end, repeaterToken: nil, fanToken: nil),
        ]),
    ]
    return MusicXMLScore(notes: fixtures.enumerated().map { ordinal, fixture in
        notationRhythmEvent(
            ordinal: ordinal,
            tick: fixture.tick,
            duration: fixture.duration,
            type: fixture.type,
            beams: fixture.beams
        )
    })
}

private func fallbackBeamRestScore() -> MusicXMLScore {
    let notes = [
        notationRhythmEvent(ordinal: 0, tick: 0, duration: 120, type: "16th"),
        notationRhythmEvent(ordinal: 1, tick: 120, duration: 120, type: "16th", isRest: true),
        notationRhythmEvent(ordinal: 2, tick: 240, duration: 120, type: "16th"),
        notationRhythmEvent(ordinal: 3, tick: 480, duration: 240, type: "eighth"),
        notationRhythmEvent(ordinal: 4, tick: 720, duration: 240, type: "eighth"),
    ]
    return MusicXMLScore(
        notes: notes,
        timeSignatureEvents: [
            MusicXMLTimeSignatureEvent(
                tick: 0,
                beats: 4,
                beatType: 4,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )
}

private func notationRhythmEvent(
    ordinal: Int,
    tick: Int,
    duration: Int,
    type: String,
    beams: [MusicXMLBeam] = [],
    isRest: Bool = false
) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        sourceID: MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: tick / 1_920,
            sourceMeasureNumberToken: String(tick / 1_920 + 1),
            staff: 1,
            voice: 1,
            sourceOrdinal: ordinal
        ),
        partID: "P1",
        measureNumber: tick / 1_920 + 1,
        tick: tick,
        durationTicks: duration,
        writtenPitch: isRest ? nil : .init(step: ["C", "D", "E", "F", "G"][ordinal % 5], octave: 4),
        writtenRhythm: .init(typeToken: type),
        midiNote: isRest ? nil : 60 + ordinal,
        isRest: isRest,
        isChord: false,
        beams: beams,
        staff: 1,
        voice: 1
    )
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
            ties: [MusicXMLTie(
                sourceID: nil,
                sourceElement: .notation,
                typeToken: "start",
                numberToken: "1",
                placementToken: "above"
            )],
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
            ties: [MusicXMLTie(
                sourceID: nil,
                sourceElement: .notation,
                typeToken: "stop",
                numberToken: "1",
                placementToken: "above"
            )],
            staff: 1,
            voice: 1
        ),
    ])
}

private func notationRestAndSpannerScore() -> MusicXMLScore {
    let sourceID: (Int, Int, Int) -> MusicXMLSourceNoteID = { ordinal, staff, voice in
        MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: staff,
            voice: voice,
            sourceOrdinal: ordinal
        )
    }
    let rests = [
        MusicXMLNoteEvent(
            sourceID: sourceID(0, 2, 2),
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            writtenRhythm: .init(typeToken: "quarter", dotCount: 1),
            midiNote: nil,
            isRest: true,
            isPrintObjectVisible: true,
            isChord: false,
            staff: 2,
            voice: 2
        ),
        MusicXMLNoteEvent(
            sourceID: sourceID(1, 2, 2),
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            writtenRhythm: .init(typeToken: "quarter"),
            midiNote: nil,
            isRest: true,
            isPrintObjectVisible: false,
            isChord: false,
            staff: 2,
            voice: 2
        ),
    ]
    let pitches = ["C", "D", "E", "F"]
    let notes = pitches.enumerated().map { index, step in
        let slurs: [MusicXMLSlur] = switch index {
        case 0:
            [.init(sourceID: nil, typeToken: "start", numberToken: "2", placementToken: "above")]
        case 1:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "2", placementToken: "above")]
        case 2:
            [.init(sourceID: nil, typeToken: "start", numberToken: "2", placementToken: "below")]
        default:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "2", placementToken: "below")]
        }
        let tuplets: [MusicXMLTuplet] = switch index {
        case 0:
            [.init(sourceID: nil, typeToken: "start", numberToken: "1", bracketToken: "yes", placementToken: "above")]
        case 1:
            [.init(sourceID: nil, typeToken: "start", numberToken: "2", bracketToken: "no", placementToken: "below")]
        case 2:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "2", bracketToken: "no", placementToken: "below")]
        default:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "1", bracketToken: "yes", placementToken: "above")]
        }
        return MusicXMLNoteEvent(
            sourceID: sourceID(index + 2, 1, 1),
            partID: "P1",
            measureNumber: 1,
            tick: index * 120,
            durationTicks: 120,
            writtenPitch: .init(step: step, octave: 4),
            writtenRhythm: .init(
                typeToken: "eighth",
                timeModification: .init(actualNotes: 3, normalNotes: 2)
            ),
            midiNote: 60 + index * 2,
            isRest: false,
            isChord: false,
            slurs: slurs,
            tuplets: tuplets,
            staff: 1,
            voice: 1
        )
    }
    return MusicXMLScore(notes: rests + notes)
}
