import Foundation
@testable import HappyPianistAVP
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

    #expect(expanded.notes.map(\.performedOccurrenceIndex) == [0, 1, 2, 3])
    #expect(Set(expanded.notes.compactMap(\.performedID)).count == expanded.notes.count)
    #expect(expanded.tempoEvents.map(\.performedOccurrenceIndex) == [0, 1, 2])
    #expect(Set(expanded.tempoEvents.compactMap(\.performedID)).count == expanded.tempoEvents.count)
    #expect(expanded.pedalEvents.map(\.performedOccurrenceIndex) == [0, 2])
    #expect(Set(expanded.pedalEvents.compactMap(\.performedID)).count == expanded.pedalEvents.count)
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
func structureExpanderHandlesImplicitStartAndMultipleSequentialRepeats() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="2">
          <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><repeat direction="backward"/></barline>
        </measure>
        <measure number="3">
          <barline location="left"><repeat direction="forward"/></barline>
          <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="4">
          <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><repeat direction="backward"/></barline>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: score)

    #expect(expanded.notes.compactMap(\.midiNote) == [60, 62, 60, 62, 64, 65, 64, 65])
    #expect(expanded.notes.map(\.performedOccurrenceIndex) == Array(0 ... 7))
    #expect(Set(expanded.notes.compactMap(\.performedID)).count == 8)
}

@Test
func structureExpanderHonorsRepeatTimesAndNestedRepeats() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <barline location="left"><repeat direction="forward"/></barline>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="2">
          <barline location="left"><repeat direction="forward"/></barline>
          <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="3">
          <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><repeat direction="backward" times="3"/></barline>
        </measure>
        <measure number="4">
          <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><repeat direction="backward"/></barline>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.repeatDirectives.compactMap(\.times) == [3])

    let result = MusicXMLStructureExpander().expandStructureIfPossible(score: score)
    #expect(result.approximationReason == nil)
    #expect(result.score.notes.compactMap(\.midiNote) == [
        60, 62, 64, 62, 64, 62, 64, 65,
        60, 62, 64, 62, 64, 62, 64, 65,
    ])
    #expect(result.score.notes.map(\.performedOccurrenceIndex) == Array(0 ... 15))

    let limited = MusicXMLStructureExpander(maxOutputMeasures: 5).expandStructureIfPossible(score: score)
    #expect(limited.approximationReason == "structure-expansion-output-measure-limit")
    #expect(limited.score == score)
}

@Test
func structureExpanderSelectsCommaSeparatedAndThirdEndingsByRepeatPass() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <barline location="left"><repeat direction="forward"/></barline>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="2">
          <barline location="left"><ending number="1, 2" type="start"/></barline>
          <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right">
            <ending number="1, 2" type="stop"/>
            <repeat direction="backward" times="3"/>
          </barline>
        </measure>
        <measure number="3">
          <barline location="left"><ending number="3" type="start"/></barline>
          <direction><sound damper-pedal="yes" time-only="3"/></direction>
          <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><ending number="3" type="stop"/></barline>
        </measure>
        <measure number="4">
          <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let result = MusicXMLStructureExpander().expandStructureIfPossible(score: score)

    #expect(result.approximationReason == nil)
    #expect(result.score.notes.compactMap(\.midiNote) == [60, 62, 60, 62, 60, 64, 65])
    #expect(result.score.pedalEvents.map(\.tick) == [2_400])
}

@Test
func structureExpanderReportsMalformedEndingInsteadOfSilentlyIgnoringIt() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <barline location="left"><ending number="1" type="start"/></barline>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><ending number="1" type="stop"/></barline>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let result = MusicXMLStructureExpander().expandStructureIfPossible(score: score)

    #expect(result.approximationReason == "structure-expansion-invalid-repeat-ending")
    #expect(result.score == score)
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
    let expanded = MusicXMLStructureExpander().expandStructureIfPossible(score: score).score

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
    let expanded = MusicXMLStructureExpander().expandStructureIfPossible(score: score).score

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
                staff: 1,
                voice: 1,
                attackTicks: nil,
                releaseTicks: nil
            ),
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
            ),
        ],
        measures: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        ],
        repeatDirectives: [],
        endingDirectives: []
    )

    let result = MusicXMLStructureExpander(maxOutputMeasures: 0).expandSoundJumpsIfPossible(score: score)
    let expanded = result.score
    #expect(result.approximationReason == "structure-expansion-output-measure-limit")
    #expect(expanded.notes == score.notes)
    #expect(expanded.tempoEvents == score.tempoEvents)
    #expect(expanded.soundDirectives == score.soundDirectives)
    #expect(expanded.measures == score.measures)
}

@Test
func structureExpanderPreservesParsedNoteAndScoreFieldsWhenMaterializing() {
    let scope = MusicXMLEventScope(partID: "P1", staff: 1, voice: 1)
    let directionID = MusicXMLDirectionSourceID(
        partID: "P1",
        sourceMeasureIndex: 1,
        sourceMeasureNumberToken: "1",
        sourceOrdinal: 0
    )
    let score = MusicXMLScore(
        partMetadata: [MusicXMLPartMetadata(partID: "P1", name: "Piano")],
        notes: [
            MusicXMLNoteEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                durationTicks: 480,
                midiNote: 60,
                isRest: false,
                isPrintObjectVisible: false,
                isChord: false,
                isGrace: true,
                graceSlash: true,
                graceStealTimePrevious: 0.2,
                graceStealTimeFollowing: 0.3,
                graceMakeTimeTicks: 90,
                ties: [.init(
                    sourceID: nil,
                    sourceElement: .notation,
                    typeToken: "start",
                    numberToken: "1",
                    placementToken: "above"
                )],
                slurs: [.init(sourceID: nil, typeToken: "start", numberToken: "2", placementToken: "below")],
                tuplets: [.init(
                    sourceID: nil,
                    typeToken: "start",
                    numberToken: "3",
                    bracketToken: "yes",
                    placementToken: "above"
                )],
                stem: .down,
                beams: [.init(numberToken: "2", value: .backwardHook, repeaterToken: nil, fanToken: nil)],
                staff: 1,
                voice: 1,
                attackTicks: -10,
                releaseTicks: 20,
                dynamicsOverrideVelocity: 88,
                articulations: [.staccato],
                arpeggiate: MusicXMLArpeggiate(numberToken: "1", directionToken: "up"),
                fingeringText: "3"
            ),
            MusicXMLNoteEvent(
                partID: "P1",
                measureNumber: 2,
                tick: 480,
                durationTicks: 480,
                midiNote: 62,
                isRest: false,
                isChord: false,
                staff: 1,
                voice: 1
            ),
        ],
        tempoEvents: [MusicXMLTempoEvent(sourceID: directionID, tick: 0, quarterBPM: 100, scope: scope)],
        dynamicEvents: [MusicXMLDynamicEvent(sourceID: directionID, tick: 0, velocity: 70, scope: scope, source: .directionDynamics)],
        wedgeEvents: [MusicXMLWedgeEvent(sourceID: directionID, tick: 0, kind: .crescendoStart, numberToken: "1", scope: scope)],
        fermataEvents: [MusicXMLFermataEvent(sourceID: directionID, tick: 0, scope: scope, source: .directionType)],
        timeSignatureEvents: [MusicXMLTimeSignatureEvent(tick: 0, beats: 4, beatType: 4, scope: scope)],
        keySignatureEvents: [MusicXMLKeySignatureEvent(tick: 0, fifths: 1, modeToken: "major", scope: scope)],
        clefEvents: [MusicXMLClefEvent(
            tick: 0,
            signToken: "G",
            line: 2,
            octaveChange: nil,
            numberToken: "1",
            scope: scope
        )],
        transposeEvents: [MusicXMLTransposeEvent(
            tick: 0, diatonic: 1, chromatic: 2, octaveChange: 0, isDouble: false, scope: scope
        )],
        octaveShiftEvents: [MusicXMLOctaveShiftEvent(
            sourceID: directionID, tick: 0, kind: .up, size: 8, numberToken: "1", scope: scope
        )],
        wordsEvents: [MusicXMLWordsEvent(sourceID: directionID, tick: 0, text: "Allegro", scope: scope)],
        measures: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 2, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        ],
        repeatDirectives: [
            MusicXMLRepeatDirective(partID: "P1", measureNumber: 1, direction: .forward),
            MusicXMLRepeatDirective(partID: "P1", measureNumber: 2, direction: .backward),
        ]
    )

    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: score)

    let preserved = expanded.notes.first
    #expect(preserved?.isGrace == true)
    #expect(preserved?.graceSlash == true)
    #expect(preserved?.graceStealTimePrevious == 0.2)
    #expect(preserved?.graceStealTimeFollowing == 0.3)
    #expect(preserved?.graceMakeTimeTicks == 90)
    #expect(preserved?.isPrintObjectVisible == false)
    #expect(preserved?.ties.first?.typeToken == "start")
    #expect(preserved?.slurs.first?.numberToken == "2")
    #expect(preserved?.tuplets.first?.bracketToken == "yes")
    #expect(preserved?.stem == .down)
    #expect(preserved?.beams.first?.value == .backwardHook)
    #expect(preserved?.attackTicks == -10)
    #expect(preserved?.releaseTicks == 20)
    #expect(preserved?.dynamicsOverrideVelocity == 88)
    #expect(preserved?.articulations == [.staccato])
    #expect(preserved?.arpeggiate == MusicXMLArpeggiate(numberToken: "1", directionToken: "up"))
    #expect(preserved?.fingeringText == "3")
    #expect(expanded.dynamicEvents.isEmpty == false)
    #expect(expanded.wedgeEvents.isEmpty == false)
    #expect(expanded.fermataEvents.isEmpty == false)
    #expect(expanded.timeSignatureEvents.isEmpty == false)
    #expect(expanded.keySignatureEvents.isEmpty == false)
    #expect(expanded.clefEvents.isEmpty == false)
    #expect(expanded.wordsEvents.isEmpty == false)
    #expect(expanded.partMetadata.map(\.partID) == ["P1"])
    #expect(expanded.tempoEvents.first?.sourceID == directionID)
    #expect(expanded.dynamicEvents.first?.sourceID == directionID)
    #expect(expanded.wedgeEvents.first?.sourceID == directionID)
    #expect(expanded.fermataEvents.first?.sourceID == directionID)
    #expect(expanded.wordsEvents.first?.sourceID == directionID)
    #expect(expanded.transposeEvents.first?.chromatic == 2)
    #expect(expanded.octaveShiftEvents.first?.sourceID == directionID)
}
