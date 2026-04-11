import Foundation

struct SingleKeyMappingRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var note: Int
    var output: KeyStroke
    var velocityThreshold: Int?

    init(
        id: UUID = UUID(),
        note: Int,
        output: KeyStroke,
        velocityThreshold: Int? = nil
    ) {
        self.id = id
        self.note = note
        self.output = output.normalized()
        self.velocityThreshold = velocityThreshold
    }
}

struct ChordMappingRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var notes: [Int]
    var output: KeyStroke

    init(id: UUID = UUID(), notes: [Int], output: KeyStroke) {
        self.id = id
        self.notes = notes
        self.output = output.normalized()
    }
}
