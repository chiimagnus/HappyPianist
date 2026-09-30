import CoreGraphics
@testable import MusicXML
@testable import Notation
@testable import Practice
import Testing

@Test
func systemCanvasKeepsExtremeNotesWithinInkBounds() {
    func makeItem(id: String, staffNumber: Int, staffStep: Int, xPosition: Double) -> GrandStaffNotationItem {
        GrandStaffNotationItem(
            occurrenceID: id,
            staffNumber: staffNumber,
            voice: 1,
            hand: staffNumber >= 2 ? .left : .right,
            tick: 0,
            xPosition: xPosition,
            staffStep: staffStep,
            displayedAccidental: nil,
            isHighlighted: false,
            fingerings: [],
            noteType: .quarter,
            noteheadGlyphToken: .noteheadBlack,
            chordID: nil,
            noteheadXOffset: 0,
            accidentalXOffsetStaffSpaces: nil,
            dotXOffsetStaffSpaces: nil,
            dotStaffStep: nil,
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

    let layout = makeNotationCanvasFixture(
        items: items,
        context: GrandStaffNotationContext()
    )

    #expect(layout.lineSpacing == 14)

    for item in items {
        let y = layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
        #expect(y >= layout.noteHeight / 2)
        #expect(y <= layout.size.height - layout.noteHeight / 2)
    }
}

@Test
func systemCanvasUsesHeaderClefLine() throws {
    let layout = makeNotationCanvasFixture(context: .init())
    let treble = try #require(layout.header.glyphs.first { $0.token == .gClef })
    let bass = try #require(layout.header.glyphs.first { $0.token == .fClef })
    #expect(abs(layout.trebleBottomLineY + treble.point.y * layout.lineSpacing - layout.yPosition(staffStep: 2, staffNumber: 1)) < 0.0001)
    #expect(abs(layout.trebleBottomLineY + bass.point.y * layout.lineSpacing - layout.yPosition(staffStep: 6, staffNumber: 2)) < 0.0001)
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

    let notation = try makeNotationSystemFixture(projection: projection)
    #expect(notation.chords.count == 2)
    #expect(notation.chords.allSatisfy { $0.itemIDs.count == 2 })
    #expect(notation.chords.allSatisfy { $0.stem.direction == .down })
    #expect(notation.beams.count == 1)
    #expect(notation.beams[0].chordIDs == notation.chords.map(\.id))
    #expect(Set(notation.items.map(\.staffNumber)) == [1, 2])
    #expect(Set(notation.items.map(\.hand)) == [.left, .right])

    let viewport = makeNotationCanvasFixture(
        items: notation.items,
        chords: notation.chords,
        beams: notation.beams
    )
    let upperStaffItem = try #require(notation.items.first { $0.staffNumber == 1 })
    let lowerStaffItem = try #require(notation.items.first { $0.staffNumber == 2 })
    #expect(viewport.yPosition(staffStep: upperStaffItem.staffStep, staffNumber: 1) !=
        viewport.yPosition(staffStep: upperStaffItem.staffStep, staffNumber: 2))
    #expect(viewport.yPosition(staffStep: lowerStaffItem.staffStep, staffNumber: 2) !=
        viewport.yPosition(staffStep: lowerStaffItem.staffStep, staffNumber: 1))
}

@Test
func repeatedPerformedOccurrencesKeepGeometryAndHighlightOnlyTheActiveOccurrence() throws {
    let score = repeatedNotationScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let repeatedEvent = try #require(plan.noteEvents.first { $0.performedNoteID.occurrenceIndex == 1 })

    #expect(projection.sourceNotes.count == 2)
    #expect(Set(projection.sourceNotes.map(\.id)) == Set(score.notes.compactMap(\.sourceID)))
    #expect(projection.performedOccurrences.count == 4)
    #expect(Set(projection.performedOccurrences.map(\.id.occurrenceIndex)) == [0, 1])

    let layout = try makeNotationSystemFixture(
        projection: projection,
        overlay: .init(
            activeEventIDs: [repeatedEvent.id],
            activeTickRange: 900 ..< 1440
        ),
        sliceWidthStaffSpaces: 12,
        sliceCenterTick: 960
    )
    let note = try #require(layout.items.first { $0.occurrenceID.hasSuffix("@1") })
    let rest = try #require(layout.rests.first { $0.id.hasSuffix("@1") })
    #expect(layout.items.count == 2)
    #expect(layout.rests.count == 2)
    #expect(note.occurrenceID.hasSuffix("@1"))
    #expect(rest.id.hasSuffix("@1"))
    #expect(note.isHighlighted)
    #expect(rest.isHighlighted == false)
    #expect(layout.items.filter(\.isHighlighted).map(\.occurrenceID) == [note.occurrenceID])
}

@Test
func repeatedPerformedScoreKeepsEveryVisibleRestOccurrence() throws {
    let performedScore = repeatedNotationScore()
    let sourceScore = MusicXMLScore(notes: Array(performedScore.notes.prefix(2)))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: performedScore),
        sourceScore: sourceScore,
        performedScore: performedScore
    )
    let layout = try makeNotationSystemFixture(
        projection: projection,
        sliceWidthStaffSpaces: 60,
        sliceCenterTick: 480
    )

    #expect(projection.sourceNotes.count == 2)
    #expect(projection.performedOccurrences.filter { occurrence in
        projection.sourceNotes.first { $0.id == occurrence.sourceNoteID }?.isRest == true
    }.map(\.id.occurrenceIndex) == [0, 1])
    #expect(layout.rests.map(\.id).allSatisfy { $0.hasSuffix("@0") || $0.hasSuffix("@1") })
    #expect(layout.rests.count == 2)
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
            writtenRhythm: .init(noteType: .eighth),
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
                writtenRhythm: .init(noteType: .quarter),
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
                writtenRhythm: .init(noteType: .quarter),
                midiNote: nil,
                isRest: true,
                isChord: false,
                staff: 2,
                voice: 2
            ),
        ]
    })
}
