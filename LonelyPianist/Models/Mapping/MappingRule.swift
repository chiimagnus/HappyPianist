import Foundation

struct SingleKeyMappingRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var note: Int
    var normalOutput: String
    var velocityThreshold: Int?
    var highVelocityOutput: String?

    init(
        id: UUID = UUID(),
        note: Int,
        normalOutput: String,
        velocityThreshold: Int? = nil,
        highVelocityOutput: String? = nil
    ) {
        self.id = id
        self.note = note
        self.normalOutput = normalOutput
        self.velocityThreshold = velocityThreshold
        self.highVelocityOutput = highVelocityOutput
    }
}

struct ChordMappingRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var notes: [Int]
    var action: MappingAction

    init(id: UUID = UUID(), notes: [Int], action: MappingAction) {
        self.id = id
        self.notes = notes
        self.action = action
    }
}

struct MelodyMappingRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var notes: [Int]
    var maxIntervalMilliseconds: Int
    var action: MappingAction

    init(
        id: UUID = UUID(),
        notes: [Int],
        maxIntervalMilliseconds: Int,
        action: MappingAction
    ) {
        self.id = id
        self.notes = notes
        self.maxIntervalMilliseconds = maxIntervalMilliseconds
        self.action = action
    }
}
