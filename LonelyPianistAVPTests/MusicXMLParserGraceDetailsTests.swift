import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserGraceDetailsTests {
    @Test
    func parserParsesGraceSlashAndStealTimeAttributes() throws {
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
                <grace slash="yes" steal-time-following="25"/>
                <pitch><step>C</step><octave>4</octave></pitch>
                <type>eighth</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        let note = try #require(score.notes.first)
        #expect(note.isGrace == true)
        #expect(note.graceSlash == true)
        #expect(note.graceStealTimePrevious == nil)
        #expect(note.graceStealTimeFollowing == 0.25)
    }
}
