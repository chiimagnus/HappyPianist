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
