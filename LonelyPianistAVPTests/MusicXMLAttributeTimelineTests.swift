@testable import LonelyPianistAVP
import Testing

@Test
func attributeTimelineResolvesLastEventsAtOrBeforeTick() {
    let timeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: [
            MusicXMLTimeSignatureEvent(tick: 0, beats: 4, beatType: 4, scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)),
            MusicXMLTimeSignatureEvent(tick: 480, beats: 3, beatType: 4, scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)),
        ],
        keySignatureEvents: [
            MusicXMLKeySignatureEvent(tick: 0, fifths: -3, modeToken: "minor", scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)),
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

    #expect(timeline.keySignature(atTick: 0)?.fifths == -3)
    #expect(timeline.keySignature(atTick: 960)?.fifths == -3)

    #expect(timeline.clef(atTick: 0, staffNumber: 1)?.signToken == "G")
    #expect(timeline.clef(atTick: 0, staffNumber: 2)?.signToken == "F")
}

