import Foundation
@testable import HappyPianistAVP
import Testing

struct MusicXMLParserArticulationsTests {
    @Test
    func parserParsesArticulationsIntoNoteEvent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
                <notations>
                  <articulations>
                    <staccato/>
                    <accent/>
                    <detached-legato/>
                  </articulations>
                </notations>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        let note = try #require(score.notes.first)
        #expect(note.articulations.contains(.staccato))
        #expect(note.articulations.contains(.accent))
        #expect(note.articulations.contains(.detachedLegato))
    }

    @Test
    func parserPreservesSourceRestVisibility() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <note print-object="no">
                <rest/>
                <duration>1</duration>
                <type>quarter</type>
                <voice>2</voice>
                <staff>2</staff>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let rest = try #require(MusicXMLParser().parse(data: Data(xml.utf8)).notes.first)
        #expect(rest.isRest)
        #expect(rest.isPrintObjectVisible == false)
        #expect(rest.staff == 2)
        #expect(rest.voice == 2)
    }
}

@Test
func parserPreservesPerformanceNotationSourceContractsAndUnsupportedKinds() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
            <voice>1</voice>
            <staff>1</staff>
            <notations>
              <slur type="start" number="2" placement="above"/>
              <tuplet type="start" number="3" bracket="yes" placement="below"/>
              <ornaments>
                <trill-mark placement="above"/>
                <mordent long="yes" approach="above"/>
                <inverted-mordent placement="below"/>
                <turn slash="yes"/>
                <inverted-turn placement="above"/>
                <tremolo type="single" placement="above">3</tremolo>
                <other-ornament placement="below">custom-token</other-ornament>
              </ornaments>
              <glissando type="start" number="4" placement="below" line-type="wavy">gliss.</glissando>
              <articulations>
                <breath-mark placement="above">comma</breath-mark>
                <caesura placement="below"/>
              </articulations>
            </notations>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let note = try #require(score.notes.first)
    let notations = note.performanceNotations

    #expect(notations.map(\.kind) == [
        .trillMark,
        .mordent,
        .invertedMordent,
        .turn,
        .invertedTurn,
        .tremolo,
        .other,
        .glissando,
        .breathMark,
        .caesura,
    ])
    #expect(notations.enumerated().allSatisfy { offset, notation in
        notation.sourceID?.sourceNoteID == note.sourceID && notation.sourceID?.sourceOrdinal == offset + 2
    })

    let slur = try #require(note.slurs.first)
    #expect(slur.typeToken == "start")
    #expect(slur.numberToken == "2")
    #expect(slur.placementToken == "above")
    #expect(slur.sourceID?.sourceOrdinal == 0)

    let tuplet = try #require(note.tuplets.first)
    #expect(tuplet.typeToken == "start")
    #expect(tuplet.numberToken == "3")
    #expect(tuplet.bracketToken == "yes")
    #expect(tuplet.placementToken == "below")
    #expect(tuplet.sourceID?.sourceOrdinal == 1)

    let mordent = try #require(notations.first { $0.kind == .mordent })
    #expect(mordent.attributes["long"] == "yes")
    #expect(mordent.attributes["approach"] == "above")

    let tremolo = try #require(notations.first { $0.kind == .tremolo })
    #expect(tremolo.typeToken == "single")
    #expect(tremolo.textToken == "3")

    let glissando = try #require(notations.first { $0.kind == .glissando })
    #expect(glissando.numberToken == "4")
    #expect(glissando.attributes["line-type"] == "wavy")
    #expect(glissando.textToken == "gliss.")

    let breath = try #require(notations.first { $0.kind == .breathMark })
    #expect(breath.textToken == "comma")

    #expect(score.performanceNotationCountsByKind["slur"] == nil)
    #expect(score.performanceNotationCountsByKind["other-ornament"] == 1)
    #expect(score.unsupportedPerformanceNotationCountsByKind == ["other-ornament": 1])
}
