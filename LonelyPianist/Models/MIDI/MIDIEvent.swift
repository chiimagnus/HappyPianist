import Foundation

struct MIDIEvent: Sendable, Equatable {
    enum EventType: Sendable, Equatable {
        case noteOn(note: Int, velocity: Int)
        case noteOff(note: Int, velocity: Int)
        case controlChange(controller: Int, value: Int)
    }

    let type: EventType
    let channel: Int
    let timestamp: Date
}
