import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserScoreVersionTests {
    @Test
    func parserRecordsScorePartwiseVersion() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.scoreVersion == "3.1")
    }

    @Test
    func parserRecordsScoreTimewiseVersionAfterConversion() throws {
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
        </score-timewise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.scoreVersion == "4.0")
    }
}
