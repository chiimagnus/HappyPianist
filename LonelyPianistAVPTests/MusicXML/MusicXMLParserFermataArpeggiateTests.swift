import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserFermataArpeggiateTests {
    @Test
    func parserParsesNoteFermataAndArpeggiate() throws {
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
                <staff>1</staff>
                <voice>1</voice>
                <notations>
                  <fermata/>
                  <arpeggiate number="1" direction="up"/>
                </notations>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        let note = try #require(score.notes.first)
        #expect(note.arpeggiate == MusicXMLArpeggiate(numberToken: "1", directionToken: "up"))

        #expect(score.fermataEvents.count == 1)
        let fermata = try #require(score.fermataEvents.first)
        #expect(fermata.tick == 0)
        #expect(fermata.source == .noteNotations)
        #expect(fermata.scope.partID == "P1")
        #expect(fermata.scope.staff == 1)
        #expect(fermata.scope.voice == 1)
    }

    @Test
    func parserParsesDirectionFermataWithStaffBackfill() throws {
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
                <direction-type><fermata/></direction-type>
                <staff>2</staff>
              </direction>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.fermataEvents.count == 1)
        let fermata = try #require(score.fermataEvents.first)
        #expect(fermata.source == .directionType)
        #expect(fermata.scope.staff == 2)
    }
}
