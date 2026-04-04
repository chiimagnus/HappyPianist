import Foundation

struct MIDIEvent: Sendable, Equatable {
    enum EventType: Sendable, Equatable {
        case noteOn
        case noteOff
    }

    let type: EventType
    let note: Int
    let velocity: Int
    let channel: Int
    let timestamp: Date
}
