import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func attributeTimelineResolvesLastEventsAtOrBeforeTick() {
    let timeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: [
            MusicXMLTimeSignatureEvent(
                tick: 0,
                beats: 4,
                beatType: 4,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
            MusicXMLTimeSignatureEvent(
                tick: 480,
                beats: 3,
                beatType: 4,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        keySignatureEvents: [
            MusicXMLKeySignatureEvent(
                tick: 0,
                fifths: -3,
                modeToken: "minor",
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        clefEvents: [
            MusicXMLClefEvent(
                tick: 0,
                signToken: "G",
                line: 2,
                octaveChange: nil,
                numberToken: "1",
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
            MusicXMLClefEvent(
                tick: 0,
                signToken: "F",
                line: 4,
                octaveChange: nil,
                numberToken: "2",
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )

    #expect(timeline.timeSignature(atTick: 0)?.beats == 4)
    #expect(timeline.timeSignature(atTick: 479)?.beats == 4)
    #expect(timeline.timeSignature(atTick: 480)?.beats == 3)
    #expect(timeline.meter(atTick: 480)?.displayText == "3/4")

    #expect(timeline.keySignature(atTick: 0)?.fifths == -3)
    #expect(timeline.keySignature(atTick: 960)?.fifths == -3)

    #expect(timeline.clef(atTick: 0, staffNumber: 1)?.signToken == "G")
    #expect(timeline.clef(atTick: 0, staffNumber: 2)?.signToken == "F")
}

@Test
func parserAndAttributeTimelinePreserveAdditiveMeterFacts() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1"><attributes><divisions>8</divisions><time symbol="normal"><beats>3+2+3</beats><beat-type>8</beat-type></time></attributes></measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let event = try #require(score.timeSignatureEvents.first)
    let timeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: score.timeSignatureEvents,
        keySignatureEvents: [],
        clefEvents: []
    )

    #expect(event.meter.components == [.init(beatGroups: [3, 2, 3], beatType: 8)])
    #expect(event.meter.displayText == "3+2+3/8")
    #expect(event.beats == 8)
    #expect(timeline.meter(atTick: 0) == event.meter)
}

@Test
func parserAndProjectionPreserveStaffAttributeTimelineStemAndBeamFacts() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>4</divisions>
            <key number="1"><fifths>2</fifths><mode>major</mode></key>
            <key number="2"><fifths>-2</fifths><mode>minor</mode></key>
            <time number="1"><beats>3+2</beats><beat-type>8</beat-type></time>
            <time number="2"><senza-misura/></time>
            <clef number="1"><sign>G</sign><line>2</line></clef>
            <clef number="2"><sign>F</sign><line>4</line></clef>
          </attributes>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice>
            <type>eighth</type><stem>down</stem>
            <beam number="1">begin</beam><beam number="2">forward hook</beam><staff>1</staff>
          </note>
          <backup><duration>4</duration></backup>
          <note>
            <pitch><step>C</step><octave>3</octave></pitch><duration>4</duration><voice>2</voice>
            <type>eighth</type><stem>up</stem><beam number="1">begin</beam><staff>2</staff>
          </note>
        </measure>
        <measure number="2">
          <attributes>
            <key number="1"><fifths>-1</fifths><mode>minor</mode></key>
            <time number="1"><beats>3</beats><beat-type>4</beat-type></time>
            <clef number="1"><sign>C</sign><line>3</line></clef>
          </attributes>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice>
            <type>quarter</type><staff>1</staff>
          </note>
        </measure>
      </part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let timeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: score.timeSignatureEvents,
        keySignatureEvents: score.keySignatureEvents,
        clefEvents: score.clefEvents
    )

    #expect(timeline.keySignature(atTick: 0, partID: "P1", staffNumber: 1)?.fifths == 2)
    #expect(timeline.keySignature(atTick: 0, partID: "P1", staffNumber: 2)?.fifths == -2)
    #expect(timeline.meter(atTick: 0, partID: "P1", staffNumber: 1)?.displayText == "3+2/8")
    #expect(timeline.meter(atTick: 0, partID: "P1", staffNumber: 2)?.isSenzaMisura == true)
    #expect(timeline.clef(atTick: 0, partID: "P1", staffNumber: 2)?.signToken == "F")
    #expect(timeline.keySignature(atTick: 480, partID: "P1", staffNumber: 1)?.fifths == -1)
    #expect(timeline.meter(atTick: 480, partID: "P1", staffNumber: 1)?.displayText == "3/4")
    #expect(timeline.clef(atTick: 480, partID: "P1", staffNumber: 1)?.signToken == "C")
    #expect(timeline.keySignature(atTick: 480, partID: "P1", staffNumber: 2)?.fifths == -2)

    #expect(score.notes[0].voice == 1)
    #expect(score.notes[0].stem == .down)
    #expect(score.notes[0].beams == [
        .init(numberToken: "1", value: .begin, repeaterToken: nil, fanToken: nil),
        .init(numberToken: "2", value: .forwardHook, repeaterToken: nil, fanToken: nil),
    ])
    #expect(score.notes[1].voice == 2)
    #expect(score.notes[1].stem == .up)
    #expect(score.notes[2].stem == .unspecified)
    #expect(score.notes[2].beams.isEmpty)

    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    #expect(projection.sourceNotes[0].keySignature == .init(fifths: 2, modeToken: "major"))
    #expect(projection.sourceNotes[0].meter?.displayText == "3+2/8")
    #expect(projection.sourceNotes[0].clef?.signToken == "G")
    #expect(projection.sourceNotes[0].stem == .down)
    #expect(projection.sourceNotes[0].beams[1].value == .forwardHook)
    #expect(projection.sourceNotes[2].keySignature == .init(fifths: -1, modeToken: "minor"))
    #expect(projection.sourceNotes[2].meter?.displayText == "3/4")
    #expect(projection.sourceNotes[2].clef?.signToken == "C")
}
