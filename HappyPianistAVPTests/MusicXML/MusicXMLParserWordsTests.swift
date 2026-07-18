import Foundation
@testable import HappyPianistAVP
import Testing

struct MusicXMLParserWordsTests {
    @Test
    func parserParsesDirectionWordsWithStaffBackfill() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <direction>
                <direction-type><words>rit.</words></direction-type>
                <staff>2</staff>
              </direction>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.wordsEvents.count == 1)
        let event = try #require(score.wordsEvents.first)
        #expect(event.tick == 0)
        #expect(event.text == "rit.")
        #expect(event.scope.staff == 2)
    }
}

@Test
func directionOffsetMovesWords() throws {
    let xml = """
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>2</divisions></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>
      <direction><direction-type><words>dolce</words></direction-type><offset>-1</offset></direction>
    </measure></part></score-partwise>
    """
    #expect(try MusicXMLParser().parse(data: Data(xml.utf8)).wordsEvents.first?.tick == 240)
}
