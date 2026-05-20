import CoreMIDI
import Foundation

struct MIDI2MessageDecoder: Sendable {
    func decode(_ message: MIDIUniversalMessage) -> MIDI2InputEvent.Kind? {
        guard message.type == .channelVoice2 else { return nil }

        let voice = message.channelVoice2
        switch voice.status {
        case .noteOn:
            return .noteOn(note: Int(voice.note.number), velocity16: voice.note.velocity)

        case .noteOff:
            return .noteOff(note: Int(voice.note.number), velocity16: voice.note.velocity)

        case .controlChange:
            return .controlChange(
                controller: Int(voice.controlChange.index),
                value32: UInt32(voice.controlChange.data)
            )

        case .programChange:
            return .programChange(program: Int(voice.programChange.program))

        case .channelPressure:
            return .channelPressure(value32: UInt32(voice.channelPressure.data))

        case .polyPressure:
            return .polyPressure(
                note: Int(voice.polyPressure.noteNumber),
                pressure32: UInt32(voice.polyPressure.pressure)
            )

        case .pitchBend:
            return .pitchBend(value32: UInt32(voice.pitchBend.data))

        default:
            return nil
        }
    }
}
