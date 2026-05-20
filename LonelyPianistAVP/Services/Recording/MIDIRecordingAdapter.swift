import Foundation

struct MIDIRecordingAdapter {
    init() {}

    func record(event: MIDI1InputEvent, into recorder: inout RecordingTakeRecorder) {
        let now = event.receivedAtUptimeSeconds
        switch event.kind {
        case let .noteOn(note, velocity):
            recorder.recordNoteOn(note: note, velocity: velocity, now: now)
        case let .noteOff(note, _):
            recorder.recordNoteOff(note: note, now: now)
        case let .controlChange(controller, value):
            recorder.recordControlChange(controller: controller, value: value, now: now)
        case let .pitchBend(value):
            recorder.recordPitchBend(value: value, now: now)
        case let .programChange(program):
            recorder.recordProgramChange(program: program, now: now)
        case let .channelPressure(value):
            recorder.recordChannelPressure(value: value, now: now)
        case let .polyPressure(note, value):
            recorder.recordPolyPressure(note: note, value: value, now: now)
        }
    }

    func record(event: MIDI2InputEvent, into recorder: inout RecordingTakeRecorder) {
        let now = event.receivedAtUptimeSeconds
        switch event.kind {
        case let .noteOn(note, velocity16):
            recorder.recordNoteOn(note: note, velocity: MIDI2ValueMapping.value16To7Bit(velocity16), now: now)
        case let .noteOff(note, _):
            recorder.recordNoteOff(note: note, now: now)
        case let .controlChange(controller, value32):
            recorder.recordControlChange(controller: controller, value: MIDI2ValueMapping.value32To7Bit(value32), now: now)
        case let .pitchBend(value32):
            recorder.recordPitchBend(value: MIDI2ValueMapping.pitchBend32To14Bit(value32), now: now)
        case let .programChange(program):
            recorder.recordProgramChange(program: program, now: now)
        case let .channelPressure(value32):
            recorder.recordChannelPressure(value: MIDI2ValueMapping.value32To7Bit(value32), now: now)
        case let .polyPressure(note, pressure32):
            recorder.recordPolyPressure(note: note, value: MIDI2ValueMapping.value32To7Bit(pressure32), now: now)
        }
    }
}
