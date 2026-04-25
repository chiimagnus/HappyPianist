@testable import LonelyPianistAVP
import Testing

@Test
func slurTimelineDetectsActiveSpanBetweenStartAndStop() {
    let timeline = MusicXMLSlurTimeline(
        events: [
            MusicXMLSlurEvent(
                tick: 0,
                kind: .start,
                numberToken: "1",
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: 1)
            ),
            MusicXMLSlurEvent(
                tick: 480,
                kind: .stop,
                numberToken: "1",
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: 1)
            ),
        ]
    )

    #expect(timeline.isActive(atTick: 0) == true)
    #expect(timeline.isActive(atTick: 240) == true)
    #expect(timeline.isActive(atTick: 480) == true)
    #expect(timeline.isActive(atTick: 481) == false)
}
