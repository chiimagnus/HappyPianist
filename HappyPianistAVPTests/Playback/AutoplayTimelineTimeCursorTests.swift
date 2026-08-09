import Foundation
@testable import MusicXML
@testable import Practice
@testable import HappyPianistAVP
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
            AutoplayPerformanceTimeline.Event(id: 3, sourceEventID: "note-60", tick: 480, kind: .noteOn(midi: 60, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 4, tick: 480, kind: .advanceStep(index: 1)),
            AutoplayPerformanceTimeline.Event(id: 5, tick: 480, kind: .advanceGuide(index: 1, guideID: 200)),
            AutoplayPerformanceTimeline.Event(id: 6, sourceEventID: "note-60", tick: 960, kind: .noteOff(midi: 60)),
        ]
    )
    let schedule = AutoplayTimelineTimeSchedule(
        timeline: timeline,
        tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
        startTick: 0
    )
    var cursor = AutoplayTimelineTimeCursor(schedule: schedule)

    #expect(schedule.timeSeconds(forEventID: 5) == 1.5)
    #expect(schedule.timeSeconds(atTick: 480) == 1.5)
    #expect(schedule.timeSeconds(atTick: 960) == 2.0)
    #expect(schedule.timeSeconds(forEventID: 3) == 1.5)
    #expect(schedule.timeSeconds(forEventID: 6) == 2.0)

    #expect(cursor.advance(toSeconds: 0) == [.step(index: 0), .guide(index: 0, guideID: 100)])
    #expect(cursor.advance(toSeconds: 0) == [])
    #expect(cursor.advance(toSeconds: 0.4) == [])

    #expect(cursor.advance(toSeconds: 1.5) == [.step(index: 1), .guide(index: 1, guideID: 200)])
    #expect(cursor.advance(toSeconds: 2.0) == [])
}
