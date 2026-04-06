import Foundation
import Testing
@testable import LonelyPianist

private final class MutableClock: ClockProtocol {
    var value: Date

    init(value: Date) {
        self.value = value
    }

    func now() -> Date {
        value
    }
}

private func noteOn(_ note: Int, velocity: Int, channel: Int = 1, at time: Date) -> MIDIEvent {
    MIDIEvent(type: .noteOn(note: note, velocity: velocity), channel: channel, timestamp: time)
}

private func noteOff(_ note: Int, channel: Int = 1, at time: Date) -> MIDIEvent {
    MIDIEvent(type: .noteOff(note: note, velocity: 0), channel: channel, timestamp: time)
}

private func cc64(_ value: Int, channel: Int = 1, at time: Date) -> MIDIEvent {
    MIDIEvent(type: .controlChange(controller: 64, value: value), channel: channel, timestamp: time)
}

@Test
func sustainDownPreventsSilenceTriggerUntilReleasedAndTimedOut() {
    let base = Date(timeIntervalSince1970: 1000)
    let clock = MutableClock(value: base)
    let service = DefaultSilenceDetectionService(clock: clock, timeoutSeconds: 2.0)

    service.reset()
    service.handle(event: noteOn(60, velocity: 90, at: base))
    service.handle(event: noteOff(60, at: base.addingTimeInterval(0.2)))
    service.handle(event: cc64(127, at: base.addingTimeInterval(0.25)))

    clock.value = base.addingTimeInterval(3.0)
    #expect(service.pollSilenceDetected() == false)

    // Release the pedal and restart the timeout gate.
    let releasedAt = base.addingTimeInterval(3.1)
    service.handle(event: cc64(0, at: releasedAt))

    clock.value = releasedAt.addingTimeInterval(1.9)
    #expect(service.pollSilenceDetected() == false)

    clock.value = releasedAt.addingTimeInterval(2.1)
    #expect(service.pollSilenceDetected() == true)
    #expect(service.pollSilenceDetected() == false)
}

@Test
func openNotePreventsSilenceTrigger() {
    let base = Date(timeIntervalSince1970: 2000)
    let clock = MutableClock(value: base)
    let service = DefaultSilenceDetectionService(clock: clock, timeoutSeconds: 2.0)

    service.reset()
    service.handle(event: noteOn(64, velocity: 100, at: base.addingTimeInterval(0.1)))

    clock.value = base.addingTimeInterval(10.0)
    #expect(service.pollSilenceDetected() == false)

    let offAt = base.addingTimeInterval(10.1)
    service.handle(event: noteOff(64, at: offAt))

    clock.value = offAt.addingTimeInterval(1.9)
    #expect(service.pollSilenceDetected() == false)

    clock.value = offAt.addingTimeInterval(2.1)
    #expect(service.pollSilenceDetected() == true)
}

