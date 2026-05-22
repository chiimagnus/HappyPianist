import Foundation
@testable import LonelyPianistAVP
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func timeCursorAdvancesStepsAndGuidesBySecondsWithoutDuplicates() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(id: 0, tick: 0, kind: .advanceStep(index: 0)),
            AutoplayPerformanceTimeline.Event(id: 1, tick: 0, kind: .advanceGuide(index: 0, guideID: 100)),
            AutoplayPerformanceTimeline.Event(id: 2, tick: 480, kind: .pauseSeconds(1.0)),
            AutoplayPerformanceTimeline.Event(id: 3, tick: 480, kind: .advanceStep(index: 1)),
            AutoplayPerformanceTimeline.Event(id: 4, tick: 480, kind: .advanceGuide(index: 1, guideID: 200)),
        ]
    )

    var cursor = AutoplayTimelineTimeCursor(
        timeline: timeline,
        tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
        startTick: 0
    )

    #expect(cursor.advance(toSeconds: 0) == [.step(index: 0), .guide(index: 0, guideID: 100)])
    #expect(cursor.advance(toSeconds: 0) == [])
    #expect(cursor.advance(toSeconds: 0.4) == [])

    #expect(cursor.advance(toSeconds: 1.5) == [.step(index: 1), .guide(index: 1, guideID: 200)])
    #expect(cursor.advance(toSeconds: 2.0) == [])
}
