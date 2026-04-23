import Foundation
import Testing

@testable import LonelyPianistAVP

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

        #expect(score.notes.count == 2)
        #expect(score.notes[0].midiNote == 60)
        #expect(score.notes[0].tick == 0)
        #expect(score.notes[1].midiNote == 62)
        #expect(score.notes[1].tick == 480)
    }
}

