import Foundation

struct RecordingTakeEvent: Codable, Equatable, Identifiable {
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

struct RecordingTake: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    let events: [RecordingTakeEvent]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, events: [RecordingTakeEvent]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.events = events
    }

    var durationSeconds: TimeInterval {
        events.map(\.time).max() ?? 0
    }
}
