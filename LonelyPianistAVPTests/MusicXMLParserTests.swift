import Foundation
@testable import LonelyPianistAVP
import Testing

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

@Test
func parserParsesSoundTempoEvents() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction>
            <sound tempo="120"/>
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
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].tick == 0)
    #expect(score.tempoEvents[0].quarterBPM == 120)
}

@Test
func parserParsesMetronomeTempoWhenSoundIsMissing() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction>
            <direction-type>
              <metronome>
                <beat-unit>quarter</beat-unit>
                <per-minute>90</per-minute>
              </metronome>
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
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].tick == 0)
    #expect(score.tempoEvents[0].quarterBPM == 90)
}

@Test
func parserPrefersSoundTempoOverMetronomeAtSameTick() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction>
            <sound tempo="100"/>
            <direction-type>
              <metronome>
                <beat-unit>quarter</beat-unit>
                <per-minute>80</per-minute>
              </metronome>
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
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].quarterBPM == 100)
}

@Test
func parserTracksTempoChangeTickUsingPartTimeline() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction><sound tempo="120"/></direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <direction><sound tempo="60"/></direction>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.tempoEvents.count == 2)
    #expect(score.tempoEvents[0].tick == 0)
    #expect(score.tempoEvents[1].tick == 480)
}

@Test
func parserIgnoresNonQuarterMetronomeInV1() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction>
            <direction-type>
              <metronome>
                <beat-unit>eighth</beat-unit>
                <per-minute>120</per-minute>
              </metronome>
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
    #expect(score.tempoEvents.isEmpty == true)
}

@Test
func parserFallsBackToOtherPartsWhenP1HasNoTempo() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
        <score-part id="P2"><part-name>Tempo</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
      <part id="P2">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction><sound tempo="140"/></direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].quarterBPM == 140)
}

@Test
func parserParsesNoteTieElement() throws {
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
            <tie type="start"/>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.notes.count == 1)
    #expect(score.notes[0].tieStart == true)
    #expect(score.notes[0].tieStop == false)
}

@Test
func parserParsesNotationsTiedElement() throws {
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
            <notations><tied type="stop"/></notations>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.notes.count == 1)
    #expect(score.notes[0].tieStart == false)
    #expect(score.notes[0].tieStop == true)
}
