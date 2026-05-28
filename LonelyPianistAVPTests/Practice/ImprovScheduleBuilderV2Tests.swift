import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func improvScheduleBuilderV2BuildsCCAndNotesWithStablePriority() {
    let events: [ImprovEvent] = [
        .note(note: 60, velocity: 90, time: 0.0, duration: 0.2),
        .cc(controller: 64, value: 127, time: 0.0),
        .cc(controller: 1, value: 64, time: 0.0), // should be ignored (not whitelisted)
    ]

    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: events, leadInSeconds: 0)

    #expect(schedule.count == 3)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(schedule[1].timeSeconds == 0.0)

    if case let .controlChange(controller, value) = schedule[0].kind {
        #expect(controller == 64)
        #expect(value == 127)
    } else {
        #expect(Bool(false))
    }

    if case let .noteOn(midi, velocity) = schedule[1].kind {
        #expect(midi == 60)
        #expect(velocity == 90)
    } else {
        #expect(Bool(false))
    }

    if case let .noteOff(midi) = schedule[2].kind {
        #expect(midi == 60)
    } else {
        #expect(Bool(false))
    }

    // A.I. Duet: reply note durations are shortened to 90%.
    #expect(abs(schedule[2].timeSeconds - 0.18) < 0.0001)
}

