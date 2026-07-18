import Foundation
@testable import HappyPianistAVP
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func manualReplayBuilderInsertsAllNotesOffAtEachStepStart() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let steps: [PracticeStep] = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
        PracticeStep(tick: 120, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
    ]

    let builder = PracticeManualReplaySequenceBuilder(chordDurationSeconds: 0.35, velocity: 96)
    let schedule = builder.buildSchedule(steps: steps, tempoMap: tempoMap, stepRange: 0 ..< 2)

    let allNotesOffEvents = schedule.filter { event in
        if case let .controlChange(controller, value) = event.kind {
            return controller == 123 && value == 0
        }
        return false
    }

    #expect(allNotesOffEvents.count == 2)
    #expect(abs(allNotesOffEvents[0].timeSeconds - 0.0) < 1e-9)
    #expect(abs(allNotesOffEvents[1].timeSeconds - 0.125) < 1e-9)
}

@Test
func manualReplayBuilderUsesStepNoteVelocities() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let steps: [PracticeStep] = [
        PracticeStep(tick: 0, notes: [
            PracticeStepNote(midiNote: 60, staff: 1, velocity: 22, handAssignment: .unknown),
            PracticeStepNote(midiNote: 60, staff: 1, velocity: 88, handAssignment: .unknown),
            PracticeStepNote(midiNote: 64, staff: 1, velocity: 40, handAssignment: .unknown),
        ]),
    ]

    let builder = PracticeManualReplaySequenceBuilder(chordDurationSeconds: 0.35, velocity: 12)
    let schedule = builder.buildSchedule(steps: steps, tempoMap: tempoMap, stepRange: 0 ..< 1)

    let noteOnEvents: [(midi: Int, velocity: UInt8)] = schedule.compactMap { event in
        if case let .noteOn(midi, velocity) = event.kind {
            return (midi, velocity)
        }
        return nil
    }

    let has60Velocity88 = noteOnEvents.contains { $0.midi == 60 && $0.velocity == 88 }
    #expect(has60Velocity88)
    let has64Velocity40 = noteOnEvents.contains { $0.midi == 64 && $0.velocity == 40 }
    #expect(has64Velocity40)
}
