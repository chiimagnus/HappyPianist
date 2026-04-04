import Foundation
import SwiftData

@Model
final class RecordingTakeEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var durationSec: TimeInterval
    @Relationship(deleteRule: .cascade, inverse: \RecordedNoteEntity.take)
    var notes: [RecordedNoteEntity]

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        durationSec: TimeInterval,
        notes: [RecordedNoteEntity] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.durationSec = durationSec
        self.notes = notes
    }
}
