import Practice
@testable import HappyPianistAVP
import Testing

@Test
func improvScheduleBuilderBuildsValidatedCCAndNotesWithStablePriority() {
    let events: [ImprovEvent] = [
        .note(note: 60, velocity: 90, time: 0.0, duration: 0.2),
        .cc(controller: 64, value: 127, time: 0.0),
    ]

    let schedule = ImprovScheduleBuilder().buildSchedule(from: events, leadInSeconds: 0)

    #expect(schedule.count == 3)
    #expect(schedule[0].kind == .controlChange(controller: 64, value: 127))
    #expect(schedule[1].kind == .noteOn(midi: 60, velocity: 90))
    #expect(schedule[2].kind == .noteOff(midi: 60))
    #expect(abs(schedule[2].timeSeconds - 0.18) < 0.0001)
}

@Test
func improvScheduleBuilderPreservesSameTimeControllerSourceOrder() {
    let schedule = ImprovScheduleBuilder().buildSchedule(from: [
        .cc(controller: 64, value: 127, time: 0),
        .cc(controller: 64, value: 0, time: 0),
    ], leadInSeconds: 0)

    #expect(schedule.map(\.kind) == [
        .controlChange(controller: 64, value: 127),
        .controlChange(controller: 64, value: 0),
    ])
}
