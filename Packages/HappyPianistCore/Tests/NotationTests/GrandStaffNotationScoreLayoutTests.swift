import Foundation
@testable import MusicXML
@testable import Notation
import Practice
import Testing

@Test
func absoluteScoreRetainsRestOnlyMeasuresAndEveryBoundary() throws {
    let score = try scoreLayoutFixture(measures: """
    <measure number="1"><attributes><divisions>1</divisions><staves>2</staves></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><type>whole</type><staff>1</staff></note></measure>
    <measure number="2"><note><rest measure="yes"/><duration>4</duration><staff>2</staff></note></measure>
    <measure number="3"><note><rest measure="yes"/><duration>4</duration><staff>1</staff></note></measure>
    """)
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    let absolute = try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    let ticks = Set(score.measures.flatMap { [$0.startTick, $0.endTick] })
    #expect(Set(absolute.notation.barlines.map(\.tick)) == ticks)
    #expect(absolute.notation.rests.count == 2)
    for measure in score.measures.dropFirst() {
        let start = try #require(absolute.spacing.barlinePositionsByTick[measure.startTick])
        let end = try #require(absolute.spacing.barlinePositionsByTick[measure.endTick])
        let rest = try #require(absolute.notation.rests.first { $0.tick == measure.startTick })
        #expect(abs(rest.xPosition - (start + end) / 2) < 0.00001)
        let slice = GrandStaffNotationSystemLayoutService().makeLayout(
            score: absolute, xRange: start...end, tickRange: measure.startTick..<measure.endTick,
            context: GrandStaffNotationContext(), overlay: .empty
        )
        #expect(slice.items.isEmpty)
        #expect(slice.rests.count == 1)
        #expect(slice.barlines.map(\.tick) == [measure.startTick, measure.endTick])
    }
}

@Test
func sourceBeamProvenanceRetainsWholeCrossMeasureGroupAfterSlicing() throws {
    let score = try scoreLayoutFixture(measures: """
    <measure number="1"><attributes><divisions>2</divisions></attributes>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">begin</beam></note>
    <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">continue</beam></note></measure>
    <measure number="2"><note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">continue</beam></note>
    <note><pitch><step>F</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">end</beam></note></measure>
    """)
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    let absolute = try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    let beam = try #require(absolute.notation.beams.first)
    guard case let .source(_, members) = beam.provenance else {
        Issue.record("explicit source beam lost provenance")
        return
    }
    #expect(members.count == 4)
    let measure = try #require(score.measures.last)
    let start = try #require(absolute.spacing.barlinePositionsByTick[measure.startTick])
    let end = try #require(absolute.spacing.barlinePositionsByTick[measure.endTick])
    let slice = GrandStaffNotationSystemLayoutService().makeLayout(
        score: absolute, xRange: start...end, tickRange: measure.startTick..<measure.endTick,
        context: nil, overlay: .empty
    )
    let clippedBeam = try #require(slice.beams.first)
    #expect(clippedBeam.chordIDs.count == 2)
    #expect(clippedBeam.provenance == beam.provenance)
    #expect(absolute.notation.beams.first?.chordIDs.count == 4)
}

@Test
func scoreFactsMapOriginalSplitPartsWithoutRemappingProjectedStaves() throws {
    let xml = """
    <score-partwise version="4.0"><part-list>
    <score-part id="upper"><part-name>Piano right hand</part-name></score-part>
    <score-part id="lower"><part-name>Piano left hand</part-name></score-part></part-list>
    <part id="upper"><measure number="1"><attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><type>whole</type><staff>1</staff></note></measure>
    <measure number="2"><note><rest measure="yes"/><duration>4</duration><staff>1</staff></note></measure></part>
    <part id="lower"><measure number="1"><attributes><divisions>1</divisions><clef><sign>F</sign><line>4</line></clef></attributes>
    <note><pitch><step>C</step><octave>3</octave></pitch><duration>4</duration><type>whole</type><staff>1</staff></note></measure>
    <measure number="2"><note><rest measure="yes"/><duration>4</duration><staff>1</staff></note></measure></part></score-partwise>
    """
    let source = try MusicXMLParser().parse(data: Data(xml.utf8))
    let score = MusicXMLPianoGrandStaffNormalizer().normalize(score: source)
    let instrument = try #require(score.logicalInstruments.first { $0.memberPartIDs.count == 2 })
    let facts = PracticeNotationScoreFacts(logicalInstrument: instrument, structuralPartID: "upper")
    #expect(facts.sourceStaff(forDisplayedStaff: 1)?.partID == "upper")
    #expect(facts.sourceStaff(forDisplayedStaff: 2)?.partID == "lower")
    #expect(facts.sourceStaff(forDisplayedStaff: 2)?.staff == 1)
    #expect(facts.sourceStaff(forDisplayedStaff: 3) == nil)
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score, logicalInstrument: instrument), sourceScore: score
    )
    #expect(Set(projection.sourceNotes.map(\.staff)) == [1, 2])
    let spans = score.measures.filter { $0.partID == "upper" }
    let absolute = try GrandStaffNotationScoreLayoutService().makeLayout(input: GrandStaffNotationScoreInput(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "split"),
        projection: projection, measureSpans: spans, facts: facts, attributeTimeline: nil
    ))
    #expect(Set(absolute.notation.items.map(\.staffNumber)) == [1, 2])
    #expect(Set(absolute.notation.rests.map(\.staffNumber)) == [1, 2])
    let single = PracticeNotationScoreFacts(
        logicalInstrument: MusicXMLLogicalInstrument(id: "single", memberPartIDs: ["P1"], classification: .piano, evidence: []),
        structuralPartID: "P1"
    )
    #expect(single.sourceStaff(forDisplayedStaff: 2)?.staff == 2)
}

@Test
func systemSliceKeepsRightEdgeClosingMarksOnPreviousMeasure() throws {
    let score = try scoreLayoutFixture(measures: """
    <measure number="1"><attributes><divisions>1</divisions></attributes>
    <barline location="left"><ending number="1" type="start"/></barline>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><type>whole</type></note>
    <barline location="right"><ending number="1" type="stop"/><repeat direction="backward"/></barline></measure>
    <measure number="2"><barline location="left"><repeat direction="forward"/></barline>
    <note><pitch><step>D</step><octave>4</octave></pitch><duration>4</duration><type>whole</type></note></measure>
    """)
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    let absolute = try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    var slices: [GrandStaffNotationLayout] = []
    for measure in score.measures {
        let start = try #require(absolute.spacing.barlinePositionsByTick[measure.startTick])
        let end = try #require(absolute.spacing.barlinePositionsByTick[measure.endTick])
        slices.append(GrandStaffNotationSystemLayoutService().makeLayout(
            score: absolute, xRange: start...end, tickRange: measure.startTick..<measure.endTick,
            context: nil, overlay: .empty
        ))
    }
    #expect(slices[0].marks.contains { $0.kind == .endingStop })
    #expect(slices[0].marks.contains { $0.kind == .repeatBackward })
    #expect(!slices[1].marks.contains { $0.kind == .endingStop || $0.kind == .repeatBackward })
    #expect(slices[1].marks.contains { $0.kind == .repeatForward })
}

@Test
func absoluteInkBoundsIncludeExtremeNotesRestsFlagsAndNestedSpanners() throws {
    let score = try scoreLayoutFixture(measures: """
    <measure number="1"><attributes><divisions>256</divisions><staves>2</staves></attributes>
    <note><pitch><step>C</step><octave>9</octave></pitch><duration>1</duration><type>1024th</type><staff>1</staff>
    <notations><slur type="start" number="1"/><tuplet type="start" number="1"/><tuplet type="start" number="2"/></notations></note>
    <note><pitch><step>D</step><octave>9</octave></pitch><duration>1</duration><type>1024th</type><staff>1</staff>
    <notations><slur type="stop" number="1"/><tuplet type="stop" number="2"/><tuplet type="stop" number="1"/></notations></note>
    <note><rest/><duration>1</duration><type>1024th</type><staff>2</staff></note>
    <note><pitch><step>C</step><octave>0</octave></pitch><duration>256</duration><type>quarter</type><staff>2</staff></note></measure>
    """)
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    let absolute = try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    let ink = absolute.ink
    #expect(ink.bounds.minY < -18)
    #expect(ink.bounds.maxY > 12)
    #expect(ink.bounds.width > 0)
    for item in absolute.notation.items { #expect(ink.boundsByElementID[item.id] != nil) }
    for rest in absolute.notation.rests { #expect(ink.boundsByElementID[rest.id] != nil) }
    for slur in absolute.notation.slurs { #expect(ink.boundsByElementID[slur.id] != nil) }
    for tuplet in absolute.notation.tuplets { #expect(ink.boundsByElementID[tuplet.id] != nil) }
    #expect(ink.boundsByElementID.values.allSatisfy { ink.bounds.contains($0) })
}

@Test
func absoluteScoreRejectsUnmappedStaffRatherThanFoldingIntoBass() throws {
    let score = try scoreLayoutFixture(measures: """
    <measure number="1"><attributes><divisions>1</divisions><staves>3</staves></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type><staff>3</staff></note></measure>
    """)
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    #expect(throws: GrandStaffNotationScoreLayoutService.ScoreLayoutError.self) {
        try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    }
}

@Test
func beamGeometryIsInvariantUnderDisplayScaleEvenAtShortSpans() throws {
    let score = try scoreLayoutFixture(measures: """
    <measure number="1"><attributes><divisions>2</divisions></attributes>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">begin</beam></note>
    <note><pitch><step>G</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam number="1">end</beam></note></measure>
    """)
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    let absolute = try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    let beam = try #require(absolute.notation.beams.first)
    let chords = absolute.notation.chords.enumerated().map { index, chord in
        var compressed = chord
        compressed.xPosition = Double(index) * 0.1
        return compressed
    }
    let byChord = Dictionary(grouping: absolute.notation.items, by: { $0.chordID ?? "" })
    func geometry(scale: CGFloat) throws -> GrandStaffChordLayoutService.BeamGeometry {
        try #require(GrandStaffChordLayoutService().beamGeometry(
            beam: beam, chords: chords, itemsByChordID: byChord, lineSpacing: scale,
            chordX: { CGFloat($0.xPosition) * scale },
            noteCenters: { items in
                Dictionary(uniqueKeysWithValues: items.map { item in
                    (item.id, CGPoint(x: 0, y: -CGFloat(item.staffStep) / 2 * scale))
                })
            }
        ))
    }
    let canonical = try geometry(scale: 1)
    let displayed = try geometry(scale: 20)
    #expect(canonical.segments.count == displayed.segments.count)
    for (first, second) in zip(canonical.segments, displayed.segments) {
        #expect(abs(first.start.y - second.start.y / 20) < 0.00001)
        #expect(abs(first.end.y - second.end.y / 20) < 0.00001)
    }
}

private func scoreLayoutFixture(measures: String) throws -> MusicXMLScore {
    try MusicXMLParser().parse(data: Data("""
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1">\(measures)</part></score-partwise>
    """.utf8))
}
