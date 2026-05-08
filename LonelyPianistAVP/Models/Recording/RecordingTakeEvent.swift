import Foundation

nonisolated struct RecordingTakeEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let time: TimeInterval
    let kind: Kind

    enum Kind: Codable, Equatable {
        case noteOn(midi: Int, velocity: Int)
        case noteOff(midi: Int)
    }

    init(id: UUID = UUID(), time: TimeInterval, kind: Kind) {
        self.id = id
        self.time = time
        self.kind = kind
    }
}
