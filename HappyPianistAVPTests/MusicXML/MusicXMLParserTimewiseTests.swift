import Foundation
@testable import HappyPianistAVP
import Testing

struct MusicXMLParserTimewiseTests {
    @Test
    func parseDataConvertsTimewiseToPartwiseBeforeParsing() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-timewise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <measure number="1">
            <part id="P1">
              <attributes><divisions>1</divisions></attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </part>
          </measure>
          <measure number="2">
            <part id="P1">
              <note>
                <pitch><step>D</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </part>
          </measure>
        </score-timewise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))

        #expect(score.notes.map(\.midiNote) == [60, 62])
        #expect(score.notes.map(\.tick) == [0, 480])
    }

    @Test
    func parseDataConvertsNamespacedTimewiseToPartwiseBeforeParsing() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mxl:score-timewise xmlns:mxl="http://www.musicxml.org" version="4.0">
          <mxl:part-list>
            <mxl:score-part id="P1"><mxl:part-name>Piano</mxl:part-name></mxl:score-part>
          </mxl:part-list>
          <mxl:measure number="1">
            <mxl:part id="P1">
              <mxl:attributes><mxl:divisions>1</mxl:divisions></mxl:attributes>
              <mxl:note>
                <mxl:pitch><mxl:step>C</mxl:step><mxl:octave>4</mxl:octave></mxl:pitch>
                <mxl:duration>1</mxl:duration>
              </mxl:note>
            </mxl:part>
          </mxl:measure>
        </mxl:score-timewise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))

        #expect(score.notes.map(\.midiNote) == [60])
        #expect(score.notes.map(\.tick) == [0])
    }
}

@Test
func timewiseConversionPreservesMetadataWrittenPitchAndSourceIdentity() throws {
    let timewise = """
    <score-timewise version="4.0">
      <part-list><score-part id="P1"><part-name>Grand Piano</part-name><score-instrument id="P1-I1"><instrument-name>Piano</instrument-name></score-instrument></score-part></part-list>
      <measure number="A"><part id="P1"><attributes><divisions>1</divisions></attributes><direction><sound tempo="90"/></direction><note><pitch><step>D</step><alter>-1</alter><octave>4</octave></pitch><accidental>flat</accidental><duration>1</duration></note></part></measure>
    </score-timewise>
    """
    let partwise = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Grand Piano</part-name><score-instrument id="P1-I1"><instrument-name>Piano</instrument-name></score-instrument></score-part></part-list>
      <part id="P1"><measure number="A"><attributes><divisions>1</divisions></attributes><direction><sound tempo="90"/></direction><note><pitch><step>D</step><alter>-1</alter><octave>4</octave></pitch><accidental>flat</accidental><duration>1</duration></note></measure></part>
    </score-partwise>
    """

    let timewiseScore = try MusicXMLParser().parse(data: Data(timewise.utf8))
    let partwiseScore = try MusicXMLParser().parse(data: Data(partwise.utf8))

    #expect(timewiseScore.partMetadata == partwiseScore.partMetadata)
    #expect(timewiseScore.notes.map(\.writtenPitch) == partwiseScore.notes.map(\.writtenPitch))
    #expect(timewiseScore.notes.map(\.sourceID) == partwiseScore.notes.map(\.sourceID))
    #expect(timewiseScore.tempoEvents.map(\.sourceID) == partwiseScore.tempoEvents.map(\.sourceID))
}
