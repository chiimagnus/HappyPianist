import Foundation
@testable import LonelyPianistAVP
import Testing

struct MusicXMLParserGraceTupletTests {
    @Test
    func parserMarksGraceNotesAndDoesNotAdvanceTick() throws {
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
                <grace/>
                <pitch><step>D</step><octave>4</octave></pitch>
              </note>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 2)
        #expect(score.notes[0].isGrace == true)
        #expect(score.notes[0].durationTicks == 0)
        #expect(score.notes[0].tick == 0)
        #expect(score.notes[1].tick == 0)

        let steps = PracticeStepBuilder().buildSteps(from: score).steps
        #expect(steps.count == 1)
        #expect(steps.first?.notes.map(\.midiNote) == [60])
    }

    @Test
    func parserDerivesTupletDurationFromTypeAndTimeModificationWhenDurationIsMissing() throws {
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
                <time-modification>
                  <actual-notes>3</actual-notes>
                  <normal-notes>2</normal-notes>
                </time-modification>
                <type>eighth</type>
              </note>
              <note>
                <pitch><step>D</step><octave>4</octave></pitch>
                <time-modification>
                  <actual-notes>3</actual-notes>
                  <normal-notes>2</normal-notes>
                </time-modification>
                <type>eighth</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 2)
        #expect(score.notes[0].durationTicks == 160)
        #expect(score.notes[0].tick == 0)
        #expect(score.notes[1].tick == 160)
    }

    @Test
    func parserDerivesDoubleDottedDurationFromTypeWhenDurationIsMissing() throws {
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
                <type>quarter</type>
                <dot/>
                <dot/>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))

        #expect(score.notes.count == 1)
        #expect(score.notes[0].durationTicks == 840)
    }
}
