import CoreGraphics
@testable import HappyPianistAVP
import Testing

@Test
func viewportLayoutKeepsExtremeNotesWithinCanvasBounds() {
    let size = CGSize(width: 800, height: 180)

    func makeItem(id: String, staffNumber: Int, staffStep: Int, xPosition: Double) -> GrandStaffNotationItem {
        GrandStaffNotationItem(
            occurrenceID: id,
            staffNumber: staffNumber,
            voice: 1,
            hand: staffNumber >= 2 ? .left : .right,
            guideID: 1,
            tick: 0,
            xPosition: xPosition,
            staffStep: staffStep,
            displayedAccidental: nil,
            isHighlighted: false,
            fingerings: [],
            noteValue: .quarter,
            chordID: nil,
            noteheadXOffset: 0,
            beamID: nil,
            durationTicks: 480,
            isGrace: false,
            articulations: [],
            arpeggiate: nil,
            dotCount: 0
        )
    }

    let items: [GrandStaffNotationItem] = [
        makeItem(id: "treble-hi", staffNumber: 1, staffStep: 26, xPosition: 0.5),
        makeItem(id: "treble-low-gap", staffNumber: 1, staffStep: -12, xPosition: 0.25),
        makeItem(id: "bass-hi-gap", staffNumber: 2, staffStep: 22, xPosition: 0.75),
        makeItem(id: "bass-low", staffNumber: 2, staffStep: -18, xPosition: 0.5),
    ]

    let layout = GrandStaffNotationViewportLayoutService().makeLayout(
        size: size,
        items: items,
        context: GrandStaffNotationContext()
    )

    #expect(layout.lineSpacing >= 8)

    for item in items {
        let y = layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
        #expect(y >= layout.noteHeight / 2)
        #expect(y <= layout.requiredHeight - layout.noteHeight / 2)
    }
}

@Test
func viewportLayoutUsesClefLineWhenProvided() {
    let size = CGSize(width: 760, height: 190)

    let context = GrandStaffNotationContext(
        trebleClefSymbol: "𝄞",
        bassClefSymbol: "𝄢",
        trebleClefSignToken: "G",
        trebleClefLine: 2,
        bassClefSignToken: "F",
        bassClefLine: 4
    )

    let layout = GrandStaffNotationViewportLayoutService().makeLayout(
        size: size,
        items: [],
        context: context
    )

    let trebleLine2Y = layout.yPosition(staffStep: 2, staffNumber: 1)
    let bassLine4Y = layout.yPosition(staffStep: 6, staffNumber: 2)
    #expect(abs(layout.trebleClefY - trebleLine2Y) < 0.0001)
    #expect(abs(layout.bassClefY - bassLine4Y) < 0.0001)
}

@Test
func crossStaffChordAndBeamKeepSourceIdentityInsteadOfHandRouting() throws {
    let score = crossStaffNotationScore()
    let sourceIDs = try score.notes.map { try #require($0.sourceID) }
    let handAssignments = Dictionary(uniqueKeysWithValues: zip(sourceIDs, score.notes).map { sourceID, note in
        let hand: ScoreHand = note.staff == 1 ? .left : .right
        return (sourceID, ScoreHandAssignment(hand: hand, provenance: .teacher))
    })
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score, handAssignments: handAssignments),
        sourceScore: score
    )

    #expect(projection.sourceNotes.map(\.staff) == [1, 2, 2, 1])
    #expect(projection.sourceNotes.map(\.voice) == [1, 1, 1, 1])
    #expect(projection.sourceNotes.map(\.chordID) == [sourceIDs[0], sourceIDs[0], sourceIDs[2], sourceIDs[2]])
    #expect(Set(projection.sourceNotes.flatMap(\.beams).map(\.groupID)).count == 1)

    let notation = GrandStaffNotationLayoutService().makeLayout(projection: projection)
    #expect(notation.chords.count == 2)
    #expect(notation.chords.allSatisfy { $0.itemIDs.count == 2 })
    #expect(notation.chords.allSatisfy { $0.stem.direction == .down })
    #expect(notation.beams.count == 1)
    #expect(notation.beams[0].chordIDs == notation.chords.map(\.id))
    #expect(Set(notation.items.map(\.staffNumber)) == [1, 2])
    #expect(Set(notation.items.map(\.hand)) == [.left, .right])

    let viewport = GrandStaffNotationViewportLayoutService().makeLayout(
        size: CGSize(width: 800, height: 220),
        items: notation.items,
        chords: notation.chords,
        beams: notation.beams,
        context: nil
    )
    let upperStaffItem = try #require(notation.items.first { $0.staffNumber == 1 })
    let lowerStaffItem = try #require(notation.items.first { $0.staffNumber == 2 })
    #expect(viewport.yPosition(staffStep: upperStaffItem.staffStep, staffNumber: 1) !=
        viewport.yPosition(staffStep: upperStaffItem.staffStep, staffNumber: 2))
    #expect(viewport.yPosition(staffStep: lowerStaffItem.staffStep, staffNumber: 2) !=
        viewport.yPosition(staffStep: lowerStaffItem.staffStep, staffNumber: 1))
}

@Test
func repeatedPerformedOccurrencesMapToOneSourceAndClipByOccurrenceTick() throws {
    let score = repeatedNotationScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let repeatedEvent = try #require(plan.noteEvents.first { $0.performedNoteID.occurrenceIndex == 1 })

    #expect(projection.sourceNotes.count == 2)
    #expect(Set(projection.sourceNotes.map(\.id)) == Set(score.notes.compactMap(\.sourceID)))
    #expect(projection.performedOccurrences.count == 4)
    #expect(Set(projection.performedOccurrences.map(\.id.occurrenceIndex)) == [0, 1])

    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(
            activeEventIDs: [repeatedEvent.id],
            activeTickRange: 900 ..< 1_440
        ),
        halfWindowTicks: 480,
        scrollTick: 960
    )
    let note = try #require(layout.items.first)
    let rest = try #require(layout.rests.first)
    #expect(layout.items.count == 1)
    #expect(layout.rests.count == 1)
    #expect(note.occurrenceID.hasSuffix("@1"))
    #expect(rest.id.hasSuffix("@1"))
    #expect(note.isHighlighted)
    #expect(rest.isHighlighted == false)
}

private func crossStaffNotationScore() -> MusicXMLScore {
    let fixtures: [(tick: Int, staff: Int, isChord: Bool, beam: MusicXMLBeamValue, pitch: MusicXMLWrittenPitch)] = [
        (0, 1, false, .begin, .init(step: "G", octave: 4)),
        (0, 2, true, .begin, .init(step: "E", octave: 4)),
        (240, 2, false, .end, .init(step: "F", octave: 4)),
        (240, 1, true, .end, .init(step: "A", octave: 4)),
    ]
    return MusicXMLScore(notes: fixtures.enumerated().map { ordinal, fixture in
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: fixture.staff,
                voice: 1,
                sourceOrdinal: ordinal
            ),
            partID: "P1",
            measureNumber: 1,
            tick: fixture.tick,
            durationTicks: 240,
            writtenPitch: fixture.pitch,
            writtenRhythm: .init(typeToken: "eighth"),
            midiNote: 60 + ordinal,
            isRest: false,
            isChord: fixture.isChord,
            stem: .down,
            beams: [.init(numberToken: "1", value: fixture.beam, repeaterToken: nil, fanToken: nil)],
            staff: fixture.staff,
            voice: 1
        )
    })
}

private func repeatedNotationScore() -> MusicXMLScore {
    let noteID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 1,
        voice: 1,
        sourceOrdinal: 0
    )
    let restID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 2,
        voice: 2,
        sourceOrdinal: 1
    )
    return MusicXMLScore(notes: [0, 1].flatMap { occurrenceIndex in
        let tick = occurrenceIndex * 960
        return [
            MusicXMLNoteEvent(
                sourceID: noteID,
                performedOccurrenceIndex: occurrenceIndex,
                partID: "P1",
                measureNumber: 1,
                tick: tick,
                durationTicks: 480,
                writtenPitch: .init(step: "C", octave: 4),
                writtenRhythm: .init(typeToken: "quarter"),
                midiNote: 60,
                isRest: false,
                isChord: false,
                staff: 1,
                voice: 1
            ),
            MusicXMLNoteEvent(
                sourceID: restID,
                performedOccurrenceIndex: occurrenceIndex,
                partID: "P1",
                measureNumber: 1,
                tick: tick,
                durationTicks: 480,
                writtenRhythm: .init(typeToken: "quarter"),
                midiNote: nil,
                isRest: true,
                isChord: false,
                staff: 2,
                voice: 2
            ),
        ]
    })
}
