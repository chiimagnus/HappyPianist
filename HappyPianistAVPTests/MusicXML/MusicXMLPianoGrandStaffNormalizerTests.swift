import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func normalizerMergesTwoPartGrandStaffNotesIntoPrimaryPart() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
        <score-part id="P2"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <clef><sign>G</sign><line>2</line></clef>
          </attributes>
          <note>
            <pitch><step>C</step><octave>5</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
      <part id="P2">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <clef><sign>F</sign><line>4</line></clef>
          </attributes>
          <note>
            <pitch><step>C</step><octave>3</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let rawScore = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(Set(rawScore.notes.map(\.partID)) == Set(["P1", "P2"]))

    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(score: rawScore)
    #expect(Set(normalized.notes.map(\.partID)) == Set(["P1"]))

    let primary = normalized.preferredPrimaryPartID(preferredPartID: "P1")
    let practiceScore = normalized.filtering(toPartID: primary)
    #expect(practiceScore.notes.count(where: { $0.isRest == false && $0.midiNote != nil }) == 2)

    let routed = MusicXMLHandRouter().routeIfNeeded(score: practiceScore)
    let hasLeftHand = routed.notes.contains { note in
        guard note.isRest == false else { return false }
        guard note.midiNote == 48 else { return false } // C3
        return (note.staff ?? 1) >= 2
    }
    #expect(hasLeftHand)
}


@Test
func logicalInstrumentModelNormalizesMemberOrderAndSupportsEquality() {
    let evidence = MusicXMLLogicalInstrumentEvidence(
        kind: .splitKeyboardPartNames,
        partIDs: ["P2", "P1"]
    )
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
