import Foundation
@testable import LonelyPianistAVP
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func manualReplayBuilderInsertsAllNotesOffAtEachStepStart() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let steps: [PracticeStep] = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 120, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
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
