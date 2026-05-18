import Foundation

nonisolated struct MIDIRecordingAdapter {
    init() {}

    func record(event: PracticeInputEvent, into recorder: inout RecordingTakeRecorder) {
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
            recorder.recordNoteOn(note: note, velocity: mapMIDI2Value16To7Bit(velocity16), now: now)
        case let .noteOff(note, _):
            recorder.recordNoteOff(note: note, now: now)
        case let .controlChange(controller, value32):
            recorder.recordControlChange(controller: controller, value: mapMIDI2Value32To7Bit(value32), now: now)
        case let .pitchBend(value32):
            recorder.recordPitchBend(value: mapMIDI2PitchBend32To14Bit(value32), now: now)
        case let .programChange(program):
            recorder.recordProgramChange(program: program, now: now)
        case let .channelPressure(value32):
            recorder.recordChannelPressure(value: mapMIDI2Value32To7Bit(value32), now: now)
        case let .polyPressure(note, pressure32):
            recorder.recordPolyPressure(note: note, value: mapMIDI2Value32To7Bit(pressure32), now: now)
        }
    }

    private func mapMIDI2Value16To7Bit(_ value: UInt16) -> Int {
        let scaled = (Double(value) / 65535.0 * 127.0).rounded()
        return max(0, min(127, Int(scaled)))
    }

    private func mapMIDI2Value32To7Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 127.0).rounded()
        return max(0, min(127, Int(scaled)))
    }

    private func mapMIDI2PitchBend32To14Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 16383.0).rounded()
        return max(0, min(16383, Int(scaled)))
    }
}
