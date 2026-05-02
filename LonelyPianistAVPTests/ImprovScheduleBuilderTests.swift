@testable import LonelyPianistAVP
import Testing

@Test
func improvScheduleBuilderSortsAndGeneratesNoteOff() {
    let notes = [
        ImprovDialogueNote(note: 64, velocity: 90, time: 0.4, duration: 0.2),
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 0.1),
        ImprovDialogueNote(note: 67, velocity: 90, time: 0.2, duration: 0.1),
    ]

    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 6)
    #expect(abs(schedule[0].timeSeconds - 0.0) < 0.0001)
    #expect(abs(schedule[5].timeSeconds - 0.6) < 0.0001)
}

@Test
func improvScheduleBuilderClampsDuration() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: -1.0),
    ]
    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 2)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(schedule[1].timeSeconds >= 0.05)
}

@Test
func improvScheduleBuilderEmptyNotesIsEmptySchedule() {
    let builder = ImprovScheduleBuilder()
    #expect(builder.buildSchedule(from: [], leadInSeconds: 0).isEmpty)
}
