import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func structureExpanderExpandsRepeatWithEndingsAndTempoEvents() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <barline location="left"><repeat direction="forward"/></barline>
          <direction>
            <direction-type><pedal type="start"/></direction-type>
          </direction>
          <direction><sound tempo="120"/></direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
        <measure number="2">
          <barline location="left"><ending number="1" type="start"/></barline>
          <direction><sound tempo="60"/></direction>
          <note>
            <pitch><step>E</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <barline location="right">
            <ending number="1" type="stop"/>
            <repeat direction="backward"/>
          </barline>
        </measure>
        <measure number="3">
          <barline location="left"><ending number="2" type="start"/></barline>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
          <barline location="right"><ending number="2" type="stop"/></barline>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: score)

    let midiNotes = expanded.notes.compactMap(\.midiNote)
    #expect(midiNotes == [60, 64, 60, 62])

    let tempoTicks = expanded.tempoEvents.map(\.tick)
    let tempoBpms = expanded.tempoEvents.map(\.quarterBPM)
    #expect(tempoTicks == [0, 480, 960])
    #expect(tempoBpms == [120, 60, 120])

    let pedalTicks = expanded.pedalEvents.map(\.tick)
    #expect(pedalTicks == [0, 960])
}

@Test
func structureExpanderFiltersTimeOnlyPedalEventsByPass() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <barline location="left"><repeat direction="forward"/></barline>
          <direction><sound damper-pedal="yes" time-only="2"/></direction>
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
          <barline location="right"><repeat direction="backward"/></barline>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: score)

    #expect(expanded.pedalEvents.count == 1)
    #expect(expanded.pedalEvents.first?.tick == 960)
    #expect(expanded.pedalEvents.first?.measureNumber == 3)
}

@Test
func structureExpanderExpandsDalSegnoJumpOnce() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction><sound segno="S1"/></direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
        <measure number="2">
          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
        <measure number="3">
          <direction><sound dalsegno="S1"/></direction>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let expanded = MusicXMLStructureExpander().expandStructureIfPossible(score: score)

    let midiNotes = expanded.notes.compactMap(\.midiNote)
    #expect(midiNotes == [60, 60, 62, 60, 60, 62])
}

@Test
func structureExpanderAssociatesBarlineSoundDirectiveWithPreviousMeasure() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Piano</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <direction><sound segno="S1"/></direction>
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
          <direction><sound dalsegno="S1"/></direction>
        </measure>
        <measure number="3">
          <note>
            <pitch><step>E</step><octave>4</octave></pitch>
            <duration>1</duration>
          </note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let expanded = MusicXMLStructureExpander().expandStructureIfPossible(score: score)

    let midiNotes = expanded.notes.compactMap(\.midiNote)
    #expect(midiNotes == [60, 62, 60, 62, 64])
}

@Test
@MainActor
func structureExpanderFallsBackWhenJumpLimitsAreHit() {
    let score = MusicXMLScore(
        notes: [
            MusicXMLNoteEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                durationTicks: 480,
                midiNote: 60,
                isRest: false,
                isChord: false,
                tieStart: false,
                tieStop: false,
                staff: 1,
                voice: 1,
                attackTicks: nil,
                releaseTicks: nil
            )
        ],
        tempoEvents: [],
        soundDirectives: [
            MusicXMLSoundDirective(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                segno: nil,
                coda: nil,
                tocoda: nil,
                dalsegno: "S1",
                dacapo: nil,
                timeOnlyPasses: nil
            )
        ],
        measures: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 480)
        ],
        repeatDirectives: [],
        endingDirectives: []
    )

    let expanded = MusicXMLStructureExpander().expandSoundJumpsIfPossible(score: score, maxOutputMeasures: 0)
    #expect(expanded.notes == score.notes)
    #expect(expanded.tempoEvents == score.tempoEvents)
    #expect(expanded.soundDirectives == score.soundDirectives)
    #expect(expanded.measures == score.measures)
}
