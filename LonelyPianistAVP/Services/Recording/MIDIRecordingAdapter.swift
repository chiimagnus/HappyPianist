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
}

