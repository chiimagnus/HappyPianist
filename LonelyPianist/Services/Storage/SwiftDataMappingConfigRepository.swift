import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataMappingConfigRepository: MappingConfigRepositoryProtocol {
    private struct ConfigDecodeFailure: Error {
        let configID: UUID
        let underlying: Error
    }

    private let context: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "Repository")

    init(context: ModelContext) {
        self.context = context

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func ensureSeedConfigIfNeeded() throws {
        let descriptor = FetchDescriptor<MappingConfigEntity>()
        let existing = try context.fetch(descriptor)

        guard existing.isEmpty else { return }

        let config = DefaultConfigFactory.makeDefaultConfig()
        context.insert(try makeEntity(from: config))
        try context.save()
        logger.info("Seeded default mapping config")
    }

    func fetchConfig() throws -> MappingConfig {
        var entities = try fetchEntitiesSorted()
        if entities.isEmpty {
            try ensureSeedConfigIfNeeded()
            entities = try fetchEntitiesSorted()
        }

        guard let entity = entities.first else {
            throw CocoaError(.coderReadCorrupt)
        }

        do {
            return try makeDomain(from: entity)
        } catch {
            logger.error(
                "Failed to decode mapping config id=\(entity.id.uuidString, privacy: .public). Resetting config. Error=\(String(describing: error), privacy: .public)"
            )
            try destructiveResetAndReseed(entities: entities)
            guard let reseeded = try fetchEntitiesSorted().first else {
                throw CocoaError(.coderReadCorrupt)
            }
            do {
                return try makeDomain(from: reseeded)
            } catch {
                throw ConfigDecodeFailure(configID: reseeded.id, underlying: error)
            }
        }
    }

    func saveConfig(_ config: MappingConfig) throws {
        let entities = try fetchEntitiesSorted()
        let payloadData = try encoder.encode(config.payload)

        if entities.isEmpty {
            context.insert(
                MappingConfigEntity(
                    id: config.id,
                    updatedAt: config.updatedAt,
                    payloadData: payloadData
                )
            )
        } else {
            for extra in entities.dropFirst() {
                context.delete(extra)
            }

            guard let primary = entities.first else {
                throw CocoaError(.coderInvalidValue)
            }

            primary.id = config.id
            primary.updatedAt = config.updatedAt
            primary.payloadData = payloadData
        }

        try context.save()
        logger.info("Saved mapping config id=\(config.id.uuidString, privacy: .public)")
    }

    private func destructiveResetAndReseed(entities: [MappingConfigEntity]) throws {
        for entity in entities {
            context.delete(entity)
        }
        try context.save()
        logger.warning("Destructive reset completed after config decode failure; reseeding config")
        try ensureSeedConfigIfNeeded()
    }

    private func fetchEntitiesSorted() throws -> [MappingConfigEntity] {
        let descriptor = FetchDescriptor<MappingConfigEntity>()
        return try context.fetch(descriptor)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func makeEntity(from config: MappingConfig) throws -> MappingConfigEntity {
        let payloadData = try encoder.encode(config.payload)
        return MappingConfigEntity(
            id: config.id,
            updatedAt: config.updatedAt,
            payloadData: payloadData
        )
    }

    private func makeDomain(from entity: MappingConfigEntity) throws -> MappingConfig {
        let payload: MappingConfigPayload
        do {
            payload = try decoder.decode(MappingConfigPayload.self, from: entity.payloadData)
        } catch {
            throw ConfigDecodeFailure(configID: entity.id, underlying: error)
        }

        return MappingConfig(
            id: entity.id,
            updatedAt: entity.updatedAt,
            payload: payload
        )
    }
}
