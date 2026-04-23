@testable import LonelyPianistAVP
import Testing

@Test
func pedalTimelineComputesIsDownAndNextChange() {
    let timeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(partID: "P1", measureNumber: 1, tick: 0, kind: .start, isDown: true, timeOnlyPasses: nil),
            MusicXMLPedalEvent(partID: "P1", measureNumber: 1, tick: 480, kind: .stop, isDown: false, timeOnlyPasses: nil),
        ]
    )

    #expect(timeline.isDown(atTick: -1) == false)
    #expect(timeline.isDown(atTick: 0) == true)
    #expect(timeline.isDown(atTick: 479) == true)
    #expect(timeline.isDown(atTick: 480) == false)

    let change0 = timeline.nextChange(afterTick: -1)
    #expect(change0?.tick == 0)
    #expect(change0?.isDown == true)

    let change1 = timeline.nextChange(afterTick: 0)
    #expect(change1?.tick == 480)
    #expect(change1?.isDown == false)

    #expect(timeline.nextChange(afterTick: 480) == nil)

    #expect(timeline.nextReleaseEdge(afterTick: -1) == 480)
    #expect(timeline.nextReleaseEdge(afterTick: 0) == 480)
    #expect(timeline.nextReleaseEdge(afterTick: 480) == nil)
}

@Test
func pedalTimelineIgnoresContinueAndCoalescesSameTickChanges() {
    let timeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(partID: "P1", measureNumber: 1, tick: 0, kind: .continue, isDown: nil, timeOnlyPasses: nil),
            MusicXMLPedalEvent(partID: "P1", measureNumber: 1, tick: 120, kind: .change, isDown: false, timeOnlyPasses: nil),
            MusicXMLPedalEvent(partID: "P1", measureNumber: 1, tick: 120, kind: .change, isDown: true, timeOnlyPasses: nil),
        ]
    )

    #expect(timeline.isDown(atTick: 0) == false)
    #expect(timeline.isDown(atTick: 119) == false)
    #expect(timeline.isDown(atTick: 120) == true)

    let change = timeline.nextChange(afterTick: 0)
    #expect(change?.tick == 120)
    #expect(change?.isDown == true)

    #expect(timeline.nextReleaseEdge(afterTick: 0) == 120)
    #expect(timeline.nextReleaseEdge(afterTick: 120) == nil)
}
