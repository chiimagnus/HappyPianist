import Foundation
import Testing
@testable import LonelyPianist

@Test
func noteOnOffProducesSingleRecordedNote() {
    let base = Date(timeIntervalSince1970: 1000)
    let service = DefaultRecordingService(clock: ClockMock(nowValue: base))

    service.startRecording(at: base)
    service.append(event: makeEvent(type: .noteOn(note: 60, velocity: 100), at: base.addingTimeInterval(0.5)))
    service.append(event: makeEvent(type: .noteOff(note: 60, velocity: 0), at: base.addingTimeInterval(1.2)))

    let take = service.stopRecording(
        at: base.addingTimeInterval(1.4),
        takeID: UUID(),
        name: "Test"
    )

    #expect(take != nil)
    #expect(take?.notes.count == 1)
    #expect(take?.notes.first?.note == 60)
    #expect(take?.notes.first?.velocity == 100)

    let startOffsetSec = take?.notes.first?.startOffsetSec ?? 0
    let durationSec = take?.notes.first?.durationSec ?? 0
    #expect(abs(startOffsetSec - 0.5) < 0.001)
    #expect(abs(durationSec - 0.7) < 0.001)
}

@Test
func stopRecordingClosesOpenNote() {
    let base = Date(timeIntervalSince1970: 2000)
    let service = DefaultRecordingService(clock: ClockMock(nowValue: base.addingTimeInterval(2.0)))

    service.startRecording(at: base)
    service.append(event: makeEvent(type: .noteOn(note: 64, velocity: 90), at: base.addingTimeInterval(0.25)))

    let take = service.stopRecording(
        at: base.addingTimeInterval(1.0),
        takeID: UUID(),
        name: "Stop Close"
    )

    #expect(take?.notes.count == 1)

    let startOffsetSec = take?.notes.first?.startOffsetSec ?? 0
    let durationSec = take?.notes.first?.durationSec ?? 0
    #expect(abs(startOffsetSec - 0.25) < 0.001)
    #expect(abs(durationSec - 0.75) < 0.001)
}

private func makeEvent(type: MIDIEvent.EventType, at date: Date) -> MIDIEvent {
    MIDIEvent(type: type, channel: 1, timestamp: date)
}
