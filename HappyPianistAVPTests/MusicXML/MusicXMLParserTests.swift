import Foundation
@testable import HappyPianistAVP
import os
import Testing

@Test
func parserCancellationAbortsDuringElementProcessing() {
    let probe = ParserCancellationProbe(cancelOnCheck: 8)
    let parser = MusicXMLParser(isCancelled: probe.callAsFunction)
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
          <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
      </part>
    </score-partwise>
    """

    #expect(throws: CancellationError.self) {
        try parser.parse(data: Data(xml.utf8))
    }
    #expect(probe.checkCount == 8)
}

@Test
func malformedXMLRemainsAParserFailure() {
    let xml = "<score-partwise><part></score-partwise>"

    #expect(throws: MusicXMLParserError.self) {
        try MusicXMLParser().parse(data: Data(xml.utf8))
    }
}

private final class ParserCancellationProbe: Sendable {
    private let cancelOnCheck: Int
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    init(cancelOnCheck: Int) {
        self.cancelOnCheck = cancelOnCheck
    }

    var checkCount: Int {
        lock.withLock { $0 }
    }

    func callAsFunction() -> Bool {
        lock.withLock { count in
            count += 1
            return count >= cancelOnCheck
        }
    }
}

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
func parserParsesMeasureLevelSoundTempoEvents() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <sound tempo="120"/>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <sound tempo="60"/>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.tempoEvents.count == 2)
    #expect(score.tempoEvents[0].tick == 0)
    #expect(score.tempoEvents[0].quarterBPM == 120)
    #expect(score.tempoEvents[1].tick == 480)
    #expect(score.tempoEvents[1].quarterBPM == 60)
}

@Test
func parserTracksMeasureIndexAndNumberToken() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1A">
          <attributes><divisions>1</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
        <measure number="2">
          <note>
            <pitch><step>D</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.measures.count == 2)
    #expect(score.measures[0].sourceMeasureIndex == 1)
    #expect(score.measures[0].measureNumber == 1)
    #expect(score.measures[0].sourceMeasureNumberToken == "1A")
    #expect(score.measures[1].sourceMeasureIndex == 2)
    #expect(score.measures[1].measureNumber == 2)
    #expect(score.measures[1].sourceMeasureNumberToken == "2")
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
func parserParsesDottedMetronomeTempo() throws {
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
                <beat-unit-dot/>
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
    #expect(score.tempoEvents[0].tick == 0)
    #expect(score.tempoEvents[0].quarterBPM == 120)
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
func parserParsesMetronomeEighthBeatUnitTempo() throws {
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
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].tick == 0)
    #expect(score.tempoEvents[0].quarterBPM == 60)
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
    #expect(score.notes[0].startsTie)
    #expect(score.notes[0].stopsTie == false)
    #expect(score.notes[0].ties.map(\.sourceElement) == [.sound])
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
    #expect(score.notes[0].startsTie == false)
    #expect(score.notes[0].stopsTie)
    #expect(score.notes[0].ties.map(\.sourceElement) == [.notation])
}

@Test
func parserParsesPedalStartAndStopEvents() throws {
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
            <direction-type><pedal type="start"/></direction-type>
          </direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <direction>
            <direction-type><pedal type="stop"/></direction-type>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.pedalEvents.count == 2)
    #expect(score.pedalEvents[0].tick == 0)
    #expect(score.pedalEvents[0].kind == .start)
    #expect(score.pedalEvents[0].value?.midiValue == 127)
    #expect(score.pedalEvents[1].tick == 480)
    #expect(score.pedalEvents[1].kind == .stop)
    #expect(score.pedalEvents[1].value?.midiValue == 0)
}

@Test
func parserParsesSoundDamperPedalEventsInsideDirection() throws {
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
            <sound damper-pedal="yes"/>
          </direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <direction>
            <sound damper-pedal="no"/>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.pedalEvents.count == 2)
    #expect(score.pedalEvents[0].tick == 0)
    #expect(score.pedalEvents[0].kind == .start)
    #expect(score.pedalEvents[0].value?.midiValue == 127)
    #expect(score.pedalEvents[1].tick == 480)
    #expect(score.pedalEvents[1].kind == .stop)
    #expect(score.pedalEvents[1].value?.midiValue == 0)
}

@Test
func parserParsesSoundDamperPedalEventsAtMeasureLevel() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <sound damper-pedal="100"/>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <sound damper-pedal="0"/>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.pedalEvents.count == 2)
    #expect(score.pedalEvents[0].tick == 0)
    #expect(score.pedalEvents[0].kind == .start)
    #expect(score.pedalEvents[0].value?.midiValue == 127)
    #expect(score.pedalEvents[1].tick == 480)
    #expect(score.pedalEvents[1].kind == .stop)
    #expect(score.pedalEvents[1].value?.midiValue == 0)
}

@Test
func parserExpandsPedalChangeIntoUpThenDownAtSameTick() throws {
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
            <direction-type><pedal type="change"/></direction-type>
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
    #expect(score.pedalEvents.count == 2)
    #expect(score.pedalEvents[0].tick == 0)
    #expect(score.pedalEvents[0].kind == .change)
    #expect(score.pedalEvents[0].value?.midiValue == 0)
    #expect(score.pedalEvents[1].tick == 0)
    #expect(score.pedalEvents[1].kind == .change)
    #expect(score.pedalEvents[1].value?.midiValue == 127)
}

@Test
func parserRecordsPedalContinueWithoutChangingState() throws {
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
            <direction-type><pedal type="continue"/></direction-type>
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
    #expect(score.pedalEvents.count == 1)
    #expect(score.pedalEvents[0].kind == .continue)
    #expect(score.pedalEvents[0].value == nil)
}

@Test
func parserIgnoresUnknownPedalType() throws {
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
            <direction-type><pedal type="??"/></direction-type>
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
    #expect(score.pedalEvents.isEmpty == true)
}

@Test
func parserAppliesDirectionOffsetToSoundTempoAndPedalEvents() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>48</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>48</duration>
          </note>
          <direction>
            <direction-type><pedal type="start"/></direction-type>
            <sound tempo="60"/>
            <offset sound="yes">-24</offset>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].tick == 240)
    #expect(score.tempoEvents[0].quarterBPM == 60)

    #expect(score.pedalEvents.count == 1)
    #expect(score.pedalEvents[0].kind == .start)
    #expect(score.pedalEvents[0].tick == 240)
}

@Test
func parserIgnoresDirectionOffsetWhenSoundGateIsNotYes() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>48</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>48</duration>
          </note>
          <direction>
            <direction-type><pedal type="start"/></direction-type>
            <sound tempo="60"/>
            <offset>-24</offset>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].tick == 480)
    #expect(score.tempoEvents[0].quarterBPM == 60)

    #expect(score.pedalEvents.count == 1)
    #expect(score.pedalEvents[0].kind == .start)
    #expect(score.pedalEvents[0].tick == 480)
}

@Test
func parserSoundOffsetOverridesDirectionOffsetForSoundEvents() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>48</divisions></attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>48</duration>
          </note>
          <direction>
            <offset sound="yes">-24</offset>
            <sound tempo="60">
              <offset>0</offset>
            </sound>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.tempoEvents.count == 1)
    #expect(score.tempoEvents[0].quarterBPM == 60)
    #expect(score.tempoEvents[0].tick == 480)
}

@Test
func parserSnapshotSupportUsesStableFieldOrdering() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let note = try #require(score.notes.first)
    let snapshot = PianoPerformanceSnapshotEncoder().encode(lines: [
        testSnapshotLine([
            ("part", note.partID),
            ("tick", String(note.tick)),
            ("midi", note.midiNote.map(String.init)),
        ]),
    ])

    expectSnapshot(snapshot, equals: "part=P1|tick=0|midi=60\n")
}

@Test
func parserPreservesPartListAndMIDIInstrumentMetadata() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1">
          <part-name>Concert Grand Piano</part-name>
          <part-abbreviation>Pno.</part-abbreviation>
          <score-instrument id="P1-I1"><instrument-name>Grand Piano</instrument-name></score-instrument>
          <midi-instrument id="P1-I1"><midi-channel>1</midi-channel><midi-program>1</midi-program><midi-bank>1</midi-bank></midi-instrument>
        </score-part>
        <score-part id="P2"><part-name>Violin</part-name></score-part>
      </part-list>
      <part id="P1"><measure number="1"/></part>
      <part id="P2"><measure number="1"/></part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))

    #expect(score.partMetadata.map(\.partID) == ["P1", "P2"])
    #expect(score.partMetadata[0].name == "Concert Grand Piano")
    #expect(score.partMetadata[0].abbreviation == "Pno.")
    #expect(score.partMetadata[0].scoreInstruments == [
        MusicXMLScoreInstrumentMetadata(id: "P1-I1", name: "Grand Piano")
    ])
    #expect(score.partMetadata[0].midiInstruments == [
        MusicXMLMIDIInstrumentMetadata(id: "P1-I1", channel: 1, program: 1, bank: 1)
    ])
}

@Test
func parserRejectsDuplicateScorePartIdentifiers() {
    let xml = """
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
        <score-part id="P1"><part-name>Duplicate</part-name></score-part>
      </part-list>
      <part id="P1"><measure number="1"/></part>
    </score-partwise>
    """

    #expect(throws: MusicXMLParserError.invalidPartMetadata(reason: "duplicate score-part id: P1")) {
        try MusicXMLParser().parse(data: Data(xml.utf8))
    }
}

@Test
func parserRejectsMissingUnknownAndDuplicateBodyPartIdentifiers() {
    let missing = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part><measure number="1"/></part>
    </score-partwise>
    """
    #expect(throws: MusicXMLParserError.invalidPartMetadata(reason: "part is missing id")) {
        try MusicXMLParser().parse(data: Data(missing.utf8))
    }

    let unknown = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P2"><measure number="1"/></part>
    </score-partwise>
    """
    #expect(throws: MusicXMLParserError.invalidPartMetadata(reason: "part references unknown score-part id: P2")) {
        try MusicXMLParser().parse(data: Data(unknown.utf8))
    }

    let duplicate = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1"/></part>
      <part id="P1"><measure number="2"/></part>
    </score-partwise>
    """
    #expect(throws: MusicXMLParserError.invalidPartMetadata(reason: "duplicate part id: P1")) {
        try MusicXMLParser().parse(data: Data(duplicate.utf8))
    }
}

@Test
func parserPreservesWrittenPitchSpellingAndDecimalAlter() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes>
        <note><pitch><step>C</step><alter>1</alter><octave>4</octave></pitch><accidental>sharp</accidental><duration>1</duration></note>
        <note><pitch><step>D</step><alter>-1</alter><octave>4</octave></pitch><accidental>flat</accidental><duration>1</duration></note>
        <note><pitch><step>F</step><alter>2</alter><octave>4</octave></pitch><accidental>double-sharp</accidental><duration>1</duration></note>
        <note><pitch><step>G</step><alter>0.5</alter><octave>4</octave></pitch><accidental>quarter-sharp</accidental><duration>1</duration></note>
        <note><rest/><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """

    let notes = try MusicXMLParser().parse(data: Data(xml.utf8)).notes

    #expect(notes[0].writtenPitch == MusicXMLWrittenPitch(step: "C", octave: 4, alter: 1, accidentalToken: "sharp"))
    #expect(notes[0].midiNote == 61)
    #expect(notes[1].writtenPitch == MusicXMLWrittenPitch(step: "D", octave: 4, alter: -1, accidentalToken: "flat"))
    #expect(notes[1].midiNote == 61)
    #expect(notes[2].writtenPitch?.alter == 2)
    #expect(notes[2].midiNote == 67)
    #expect(notes[3].writtenPitch?.alter == 0.5)
    #expect(notes[3].midiNote == nil)
    #expect(notes[4].writtenPitch == nil)
}

@Test
func parserPreservesTransposeAndOctaveShiftFacts() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Clarinet and Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions><transpose><diatonic>-1</diatonic><chromatic>-2</chromatic><octave-change>0</octave-change></transpose></attributes>
          <direction><direction-type><octave-shift type="up" size="8" number="1"/></direction-type></direction>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="2"><direction><direction-type><octave-shift type="stop" size="8" number="1"/></direction-type></direction></measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))

    #expect(score.transposeEvents == [
        MusicXMLTransposeEvent(
            tick: 0,
            diatonic: -1,
            chromatic: -2,
            octaveChange: 0,
            isDouble: false,
            scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
        )
    ])
    #expect(score.notes.first?.writtenPitch?.step == "C")
    #expect(score.octaveShiftEvents.map(\.kind) == [.up, .stop])
    #expect(score.octaveShiftEvents.map(\.tick) == [0, 480])
}

@Test
func partSelectorPrefersTheOnlyExplicitPianoOverNoteCount() {
    let piano = MusicXMLLogicalInstrument(
        id: "piano:P2",
        memberPartIDs: ["P2"],
        classification: .piano,
        evidence: [.init(kind: .explicitPianoMetadata, partIDs: ["P2"])]
    )
    let orchestra = MusicXMLLogicalInstrument(
        id: "other:P1",
        memberPartIDs: ["P1"],
        classification: .other,
        evidence: [.init(kind: .singlePlayablePart, partIDs: ["P1"])]
    )
    let score = MusicXMLScore(
        logicalInstruments: [orchestra, piano],
        notes: [
            MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: 60, isRest: false, isChord: false, staff: 1, voice: 1),
            MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 1, durationTicks: 1, midiNote: 62, isRest: false, isChord: false, staff: 1, voice: 1),
            MusicXMLNoteEvent(partID: "P2", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: 48, isRest: false, isChord: false, staff: 1, voice: 1),
        ]
    )
    #expect(MusicXMLPracticePartSelector().select(from: score) == .selected(piano))
}

@Test
func partSelectorReportsAmbiguityInsteadOfPickingTheMostNotes() {
    let a = MusicXMLLogicalInstrument(
        id: "other:P1", memberPartIDs: ["P1"], classification: .other,
        evidence: [.init(kind: .singlePlayablePart, partIDs: ["P1"])]
    )
    let b = MusicXMLLogicalInstrument(
        id: "other:P2", memberPartIDs: ["P2"], classification: .other,
        evidence: [.init(kind: .singlePlayablePart, partIDs: ["P2"])]
    )
    let score = MusicXMLScore(
        logicalInstruments: [a, b],
        notes: [
            MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: 60, isRest: false, isChord: false, staff: 1, voice: 1),
            MusicXMLNoteEvent(partID: "P2", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: 48, isRest: false, isChord: false, staff: 1, voice: 1),
        ]
    )
    #expect(MusicXMLPracticePartSelector().select(from: score) == .ambiguous(.init(
        candidateInstrumentIDs: ["other:P1", "other:P2"],
        reason: "multiple-playable-instruments-without-piano-evidence"
    )))
}
