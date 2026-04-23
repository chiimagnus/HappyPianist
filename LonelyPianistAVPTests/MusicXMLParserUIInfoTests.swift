import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserUIInfoTests {
    @Test
    func parserParsesFingeringTextFromTechnicalNotations() throws {
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
                  <technical><fingering>3</fingering></technical>
                </notations>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        #expect(score.notes.first?.fingeringText == "3")
    }

    @Test
    func parserParsesSlurStartStopEventsFromNotations() throws {
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
                  <slur type="start" number="1"/>
                </notations>
              </note>
              <note>
                <pitch><step>D</step><octave>4</octave></pitch>
                <duration>1</duration>
                <staff>1</staff>
                <voice>1</voice>
                <notations>
                  <slur type="stop" number="1"/>
                </notations>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.slurEvents.count == 2)
        #expect(score.slurEvents[0].kind == .start)
        #expect(score.slurEvents[0].numberToken == "1")
        #expect(score.slurEvents[0].scope.staff == 1)
        #expect(score.slurEvents[1].kind == .stop)
        #expect(score.slurEvents[1].numberToken == "1")
    }

    @Test
    func parserParsesTimeKeyAndClefEventsFromAttributes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <time><beats>3</beats><beat-type>4</beat-type></time>
                <key><fifths>-1</fifths><mode>minor</mode></key>
                <clef number="2"><sign>F</sign><line>4</line></clef>
              </attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.timeSignatureEvents.count == 1)
        #expect(score.timeSignatureEvents.first?.beats == 3)
        #expect(score.timeSignatureEvents.first?.beatType == 4)
        #expect(score.keySignatureEvents.count == 1)
        #expect(score.keySignatureEvents.first?.fifths == -1)
        #expect(score.keySignatureEvents.first?.modeToken == "minor")
        #expect(score.clefEvents.count == 1)
        #expect(score.clefEvents.first?.signToken == "F")
        #expect(score.clefEvents.first?.line == 4)
        #expect(score.clefEvents.first?.numberToken == "2")
        #expect(score.clefEvents.first?.scope.staff == 2)
    }
}
