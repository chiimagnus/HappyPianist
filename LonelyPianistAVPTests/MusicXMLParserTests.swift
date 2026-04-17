import Foundation
import Testing
@testable import LonelyPianistAVP

@Test
func parserHandlesChordAndBackupTimeline() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>2</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>2</duration>
          </note>
          <note>
            <chord/>
            <pitch><step>E</step><octave>4</octave></pitch>
            <duration>2</duration>
          </note>
          <note>
            <rest/>
            <duration>2</duration>
          </note>
          <backup><duration>4</duration></backup>
          <note>
            <pitch><step>G</step><octave>3</octave></pitch>
            <duration>4</duration>
            <staff>2</staff>
            <voice>2</voice>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.notes.count == 4)

    #expect(score.notes[0].tick == 0)
    #expect(score.notes[0].midiNote == 60)
    #expect(score.notes[0].isChord == false)

    #expect(score.notes[1].tick == 0)
    #expect(score.notes[1].midiNote == 64)
    #expect(score.notes[1].isChord == true)

    #expect(score.notes[2].tick == 480)
    #expect(score.notes[2].isRest == true)

    #expect(score.notes[3].tick == 0)
    #expect(score.notes[3].midiNote == 55)
    #expect(score.notes[3].staff == 2)
    #expect(score.notes[3].voice == 2)
}

@Test
func parserHandlesForwardAcrossMeasures() throws {
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
            <duration>2</duration>
          </note>
        </measure>
        <measure number="2">
          <forward><duration>2</duration></forward>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.notes.count == 2)
    #expect(score.notes[0].tick == 0)
    #expect(score.notes[1].tick == 1920)
    #expect(score.notes[1].midiNote == 62)
}
