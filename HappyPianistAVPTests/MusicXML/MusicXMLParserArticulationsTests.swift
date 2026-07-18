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
        .slur,
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
        notation.sourceID?.sourceNoteID == note.sourceID && notation.sourceID?.sourceOrdinal == offset
    })

    let slur = try #require(notations.first { $0.kind == .slur })
    #expect(slur.typeToken == "start")
    #expect(slur.numberToken == "2")
    #expect(slur.placementToken == "above")

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

    #expect(score.performanceNotationCountsByKind["slur"] == 1)
    #expect(score.performanceNotationCountsByKind["other-ornament"] == 1)
    #expect(score.unsupportedPerformanceNotationCountsByKind == ["other-ornament": 1])
}
