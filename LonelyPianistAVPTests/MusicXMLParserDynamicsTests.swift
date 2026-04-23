import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserDynamicsTests {
    @Test
    func parserParsesDirectionTypeDynamicsMarkIntoDynamicEvents() throws {
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
                  <dynamics><mf/></dynamics>
                </direction-type>
              </direction>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.dynamicEvents.count == 1)
        let event = try #require(score.dynamicEvents.first)
        #expect(event.tick == 0)
        #expect(event.velocity == 75)
        #expect(event.scope.partID == "P1")
        #expect(event.scope.staff == nil)
        #expect(event.source == .directionDynamics)
    }

    @Test
    func parserParsesSoundDynamicsAttributeIntoDynamicEventsWithDirectionStaff() throws {
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
                <sound dynamics="64"/>
                <staff>2</staff>
              </direction>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.dynamicEvents.count == 1)
        let event = try #require(score.dynamicEvents.first)
        #expect(event.tick == 0)
        #expect(event.velocity == 64)
        #expect(event.scope.partID == "P1")
        #expect(event.scope.staff == 2)
        #expect(event.source == .soundDynamicsAttribute)
    }

    @Test
    func parserParsesNoteDynamicsOverrideIntoNoteEvent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <note dynamics="100">
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        #expect(score.notes.first?.dynamicsOverrideVelocity == 100)
    }
}
