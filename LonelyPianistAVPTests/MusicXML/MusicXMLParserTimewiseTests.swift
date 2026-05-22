import Foundation
@testable import LonelyPianistAVP
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
