import CoreMIDI
import Foundation

struct MIDI1MessageDecoder: Sendable {
    func decode(_ message: MIDIUniversalMessage) -> MIDI1InputEvent.Kind? {
        guard message.type == .channelVoice1 else { return nil }

        let voice = message.channelVoice1
        switch voice.status {
        case .noteOn:
            let note = Int(voice.note.number)
            let velocity = Int(voice.note.velocity)
            if velocity == 0 {
                return .noteOff(note: note, velocity: 0)
            }
            return .noteOn(note: note, velocity: velocity)

        case .noteOff:
            let note = Int(voice.note.number)
            let velocity = Int(voice.note.velocity)
            return .noteOff(note: note, velocity: velocity)

        case .controlChange:
            let controller = Int(voice.controlChange.index)
            let value = Int(voice.controlChange.data)
            return .controlChange(controller: controller, value: value)

        case .programChange:
            return .programChange(program: Int(voice.program))

        case .channelPressure:
            return .channelPressure(value: Int(voice.channelPressure))

        case .polyPressure:
            return .polyPressure(
                note: Int(voice.polyPressure.noteNumber),
                value: Int(voice.polyPressure.pressure)
            )

        case .pitchBend:
            return .pitchBend(value: Int(voice.pitchBend))

        default:
            return nil
        }
    }
}
