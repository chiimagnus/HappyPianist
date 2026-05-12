import Foundation

nonisolated struct RecordingTakeEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let time: TimeInterval
    let kind: Kind

    enum Kind: Codable, Equatable {
        case noteOn(midi: Int, velocity: Int)
        case noteOff(midi: Int)
        case controlChange(controller: Int, value: Int)
        case pitchBend(value: Int)
        case programChange(program: Int)
        case channelPressure(value: Int)
        case polyPressure(midi: Int, value: Int)
    }

    init(id: UUID = UUID(), time: TimeInterval, kind: Kind) {
        self.id = id
        self.time = time
        self.kind = kind
    }
}
