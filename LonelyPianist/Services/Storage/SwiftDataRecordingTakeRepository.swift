import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataRecordingTakeRepository: RecordingTakeRepositoryProtocol {
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "RecordingRepository")

    init(context: ModelContext) {
        self.context = context
    }

    func fetchTakes() throws -> [RecordingTake] {
        let descriptor = FetchDescriptor<RecordingTakeEntity>()
        let entities = try context.fetch(descriptor)
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }

        return entities.map(makeDomain)
    }

    func saveTake(_ take: RecordingTake) throws {
        if let existing = try fetchEntity(id: take.id) {
            existing.name = take.name
            existing.createdAt = take.createdAt
            existing.updatedAt = take.updatedAt
            existing.durationSec = take.durationSec

            for noteEntity in existing.notes {
                context.delete(noteEntity)
            }
            existing.notes.removeAll(keepingCapacity: false)

            for note in take.notes {
                let noteEntity = makeNoteEntity(from: note)
                noteEntity.take = existing
                existing.notes.append(noteEntity)
                context.insert(noteEntity)
            }
        } else {
            let entity = RecordingTakeEntity(
                id: take.id,
                name: take.name,
                createdAt: take.createdAt,
                updatedAt: take.updatedAt,
                durationSec: take.durationSec
            )

            for note in take.notes {
                let noteEntity = makeNoteEntity(from: note)
                noteEntity.take = entity
                entity.notes.append(noteEntity)
                context.insert(noteEntity)
            }

            context.insert(entity)
        }

        try context.save()
        logger.info("Saved take: \(take.name, privacy: .public)")
    }

    func deleteTake(id: UUID) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        context.delete(entity)
        try context.save()
        logger.info("Deleted take id: \(id.uuidString, privacy: .public)")
    }

    func renameTake(id: UUID, name: String) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        entity.name = name
        entity.updatedAt = .now
        try context.save()
        logger.info("Renamed take id: \(id.uuidString, privacy: .public)")
    }

    private func fetchEntity(id: UUID) throws -> RecordingTakeEntity? {
        var descriptor = FetchDescriptor<RecordingTakeEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeDomain(from entity: RecordingTakeEntity) -> RecordingTake {
        let notes = entity.notes
            .sorted { lhs, rhs in
                if lhs.startOffsetSec != rhs.startOffsetSec {
                    return lhs.startOffsetSec < rhs.startOffsetSec
                }
                if lhs.note != rhs.note {
                    return lhs.note < rhs.note
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { note in
                RecordedNote(
                    id: note.id,
                    note: note.note,
                    velocity: note.velocity,
                    channel: note.channel,
                    startOffsetSec: note.startOffsetSec,
                    durationSec: note.durationSec
                )
            }

        return RecordingTake(
            id: entity.id,
            name: entity.name,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            durationSec: entity.durationSec,
            notes: notes
        )
    }

    private func makeNoteEntity(from note: RecordedNote) -> RecordedNoteEntity {
        RecordedNoteEntity(
            id: note.id,
            note: note.note,
            velocity: note.velocity,
            channel: note.channel,
            startOffsetSec: note.startOffsetSec,
            durationSec: note.durationSec
        )
    }
}
