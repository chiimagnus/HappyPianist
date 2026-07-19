import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func logicalInstrumentModelNormalizesMemberOrderAndSupportsEquality() {
    let evidence = MusicXMLLogicalInstrumentEvidence(kind: .splitKeyboardPartNames, partIDs: ["P2", "P1"])
    let lhs = MusicXMLLogicalInstrument(
        id: "piano:P1+P2",
        memberPartIDs: ["P2", "P1", "P1"],
        classification: .piano,
        evidence: [evidence]
    )
    let rhs = MusicXMLLogicalInstrument(
        id: "piano:P1+P2",
        memberPartIDs: ["P1", "P2"],
        classification: .piano,
        evidence: [evidence]
    )
    #expect(lhs == rhs)
    #expect(lhs.memberPartIDs == ["P1", "P2"])
}

@Test
func normalizerGroupsExplicitSplitPianoWithoutRewritingSourceParts() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list>
        <score-part id="RH"><part-name>Piano RH</part-name></score-part>
        <score-part id="LH"><part-name>Piano LH</part-name></score-part>
      </part-list>
      <part id="RH"><measure number="1"><attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
        <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration></note>
      </measure></part>
      <part id="LH"><measure number="1"><attributes><divisions>1</divisions><clef><sign>F</sign><line>4</line></clef></attributes>
        <direction><direction-type><dynamics><p/></dynamics></direction-type></direction>
        <note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """
    let raw = try MusicXMLParser().parse(data: Data(xml.utf8))
    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(score: raw)
    let piano = try #require(normalized.logicalInstruments.only)
    let filtered = normalized.filtering(toLogicalInstrument: piano)

    #expect(piano.classification == .piano)
    #expect(piano.memberPartIDs == ["LH", "RH"])
    #expect(piano.grandStaffPartAssignments == [
        MusicXMLGrandStaffPartAssignment(partID: "LH", role: .lower),
        MusicXMLGrandStaffPartAssignment(partID: "RH", role: .upper),
    ])
    #expect(filtered.notes.allSatisfy { $0.staff == nil })
    #expect(Set(filtered.notes.map(\.partID)) == ["LH", "RH"])
    #expect(filtered.dynamicEvents.contains { $0.scope.partID == "LH" })
    #expect(Set(filtered.measures.map(\.partID)) == ["LH", "RH"])
}

@Test
func normalizerDoesNotMergeDistinctNamedPianosFromComplementaryClefs() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1"><part-name>Piano 1</part-name></score-part>
        <score-part id="P2"><part-name>Piano 2</part-name></score-part>
      </part-list>
      <part id="P1"><measure number="1"><attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
        <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration></note>
      </measure></part>
      <part id="P2"><measure number="1"><attributes><divisions>1</divisions><clef><sign>F</sign><line>4</line></clef></attributes>
        <note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """

    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(
        score: try MusicXMLParser().parse(data: Data(xml.utf8))
    )

    #expect(normalized.logicalInstruments.count == 2)
    #expect(normalized.logicalInstruments.allSatisfy { $0.memberPartIDs.count == 1 })
}

@Test
func normalizerDoesNotMergeIndependentTrebleAndBassInstruments() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1"><part-name>Flute</part-name></score-part>
        <score-part id="P2"><part-name>Cello</part-name></score-part>
      </part-list>
      <part id="P1"><measure number="1"><attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
        <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration></note>
      </measure></part>
      <part id="P2"><measure number="1"><attributes><divisions>1</divisions><clef><sign>F</sign><line>4</line></clef></attributes>
        <note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """
    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(
        score: try MusicXMLParser().parse(data: Data(xml.utf8))
    )
    #expect(normalized.logicalInstruments.count == 2)
    #expect(normalized.logicalInstruments.allSatisfy { $0.memberPartIDs.count == 1 })
    #expect(normalized.logicalInstruments.allSatisfy { $0.classification == .other })
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}

@Test
func goldenFixtureDoesNotClassifyIndependentInstrumentsAsOnePiano() throws {
    let fixture = try PianoPerformanceFixtureLoader().fixture(id: "two-instrument-not-piano")
    let parsed = try MusicXMLParser().parse(fileURL: fixture.url)
    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(score: parsed)

    #expect(normalized.logicalInstruments.count == 2)
    #expect(Set(normalized.logicalInstruments.flatMap(\.memberPartIDs)) == ["FL", "VC"])
    #expect(normalized.logicalInstruments.allSatisfy { $0.classification == .other })
    #expect(Set(normalized.notes.map(\.partID)) == ["FL", "VC"])
    #expect(Set(normalized.measures.map(\.partID)) == ["FL", "VC"])
}

@Test
func splitPianoGoldenFixturePreservesAllPartsAndPerformedOccurrences() throws {
    let fixture = try PianoPerformanceFixtureLoader().fixture(id: "split-part-grand-staff-piano")
    let parsed = try MusicXMLParser().parse(fileURL: fixture.url)
    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(score: parsed)
    let piano = try #require(normalized.logicalInstruments.only)
    let source = normalized.filtering(toLogicalInstrument: piano)

    #expect(piano.classification == .piano)
    #expect(piano.memberPartIDs == ["LH", "RH"])
    #expect(Set(source.notes.map(\.partID)) == ["LH", "RH"])
    #expect(Set(source.measures.map(\.partID)) == ["LH", "RH"])
    #expect(source.dynamicEvents.map(\.scope.partID) == ["LH"])
    #expect(Set(source.pedalEvents.map(\.partID)) == ["LH"])
    #expect(source.tempoEvents.map(\.scope.partID) == ["RH"])
    #expect(source.repeatDirectives.map(\.partID) == ["RH", "RH"])

    let performed = MusicXMLStructureExpander().expandStructureIfPossible(
        score: source,
        primaryPartID: "RH",
        includedPartIDs: Set(piano.memberPartIDs)
    ).score

    #expect(performed.notes.compactMap(\.midiNote) == [48, 72, 43, 74, 48, 72, 43, 74])
    #expect(Set(performed.notes.map(\.partID)) == ["LH", "RH"])
    #expect(Set(performed.notes.compactMap(\.performedID)).count == performed.notes.count)
    #expect(Set(performed.notes.compactMap(\.sourceID)).count == 4)
    #expect(performed.dynamicEvents.count == 2)
    #expect(performed.pedalEvents.count == 4)
    #expect(performed.tempoEvents.count == 2)
    #expect(performed.measures.count == 8)
    #expect(Set(performed.measures.map(\.partID)) == ["LH", "RH"])
    #expect(performed.measures.filter { $0.partID == "RH" }.map(\.occurrenceIndex) == [0, 1, 2, 3])
    #expect(performed.measures.filter { $0.partID == "LH" }.map(\.occurrenceIndex) == [0, 1, 2, 3])
    #expect(performed.measures.filter { $0.partID == "LH" }.map(\.sourceMeasureIndex) == [1, 2, 1, 2])
}
