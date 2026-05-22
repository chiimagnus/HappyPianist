import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserWedgeTests {
    @Test
    func parserParsesWedgeEventsWithDirectionStaffBackfill() throws {
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
                <direction-type>
                  <wedge type="crescendo" number="1"/>
                </direction-type>
                <staff>2</staff>
              </direction>
              <direction>
                <direction-type>
                  <wedge type="stop" number="1"/>
                </direction-type>
                <staff>2</staff>
              </direction>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.wedgeEvents.count == 2)
        let first = score.wedgeEvents[0]
        let second = score.wedgeEvents[1]
        #expect(first.kind == .crescendoStart)
        #expect(second.kind == .stop)
        #expect(first.numberToken == "1")
        #expect(second.numberToken == "1")
        #expect(first.scope.partID == "P1")
        #expect(first.scope.staff == 2)
        #expect(second.scope.staff == 2)
    }
}
