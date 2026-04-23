import Foundation
@testable import LonelyPianistAVP
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
