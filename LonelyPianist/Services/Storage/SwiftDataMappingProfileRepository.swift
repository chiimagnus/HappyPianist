import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataMappingProfileRepository: MappingProfileRepositoryProtocol {
    private struct ProfileDecodeFailure: Error {
        let profileID: UUID
        let profileName: String
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

    func ensureSeedProfilesIfNeeded() throws {
        let descriptor = FetchDescriptor<MappingProfileEntity>()
        let existing = try context.fetch(descriptor)

        guard existing.isEmpty else { return }

        for profile in DefaultProfileFactory.makeProfiles() {
            let entity = try makeEntity(from: profile)
            context.insert(entity)
        }

        try context.save()
        logger.info("Seeded default mapping profiles")
    }

    func fetchProfiles() throws -> [MappingProfile] {
        let entities = try fetchEntitiesSorted()
        logger.debug("Fetched profiles count: \(entities.count, privacy: .public)")

        do {
            return try decodeProfiles(from: entities)
        } catch let failure as ProfileDecodeFailure {
            logger.error(
                "Failed to decode payload for profile id=\(failure.profileID.uuidString, privacy: .public), name=\(failure.profileName, privacy: .public). Resetting all profiles. Error=\(String(describing: failure.underlying), privacy: .public)"
            )

            for entity in entities {
                context.delete(entity)
            }
            try context.save()
            logger.warning("Destructive reset completed after decode failure; reseeding profiles")

            try ensureSeedProfilesIfNeeded()

            let reseededEntities = try fetchEntitiesSorted()
            logger.debug("Fetched reseeded profiles count: \(reseededEntities.count, privacy: .public)")
            do {
                return try decodeProfiles(from: reseededEntities)
            } catch let reseedFailure as ProfileDecodeFailure {
                logger.critical(
                    "Reseeded profiles still fail to decode. id=\(reseedFailure.profileID.uuidString, privacy: .public), name=\(reseedFailure.profileName, privacy: .public), error=\(String(describing: reseedFailure.underlying), privacy: .public)"
                )
                throw reseedFailure
            }
        }
    }

    func saveProfile(_ profile: MappingProfile) throws {
        if let existing = try fetchEntity(id: profile.id) {
            existing.name = profile.name
            existing.isBuiltIn = profile.isBuiltIn
            existing.isActive = profile.isActive
            existing.createdAt = profile.createdAt
            existing.updatedAt = profile.updatedAt
            existing.payloadData = try encoder.encode(profile.payload)
        } else {
            context.insert(try makeEntity(from: profile))
        }

        try context.save()
        logger.info("Saved profile: \(profile.name, privacy: .public)")
    }

    func deleteProfile(id: UUID) throws {
        guard let entity = try fetchEntity(id: id) else { return }

        let wasActive = entity.isActive
        context.delete(entity)
        try context.save()
        logger.info("Deleted profile id: \(id.uuidString, privacy: .public)")

        if wasActive {
            try activateMostRecentlyUpdatedProfile()
        }
    }

    func setActiveProfile(id: UUID) throws {
        let descriptor = FetchDescriptor<MappingProfileEntity>()
        let entities = try context.fetch(descriptor)

        for entity in entities {
            let shouldActivate = entity.id == id
            entity.isActive = shouldActivate
            if shouldActivate {
                entity.updatedAt = .now
            }
        }

        try context.save()
        logger.info("Activated profile id: \(id.uuidString, privacy: .public)")
    }

    private func activateMostRecentlyUpdatedProfile() throws {
        let descriptor = FetchDescriptor<MappingProfileEntity>()
        if let entity = try context.fetch(descriptor).max(by: { $0.updatedAt < $1.updatedAt }) {
            entity.isActive = true
            entity.updatedAt = .now
            try context.save()
        }
    }

    private func fetchEntity(id: UUID) throws -> MappingProfileEntity? {
        var descriptor = FetchDescriptor<MappingProfileEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchEntitiesSorted() throws -> [MappingProfileEntity] {
        let descriptor = FetchDescriptor<MappingProfileEntity>()
        return try context.fetch(descriptor)
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func decodeProfiles(from entities: [MappingProfileEntity]) throws -> [MappingProfile] {
        try entities.map { entity in
            do {
                return try makeDomain(from: entity)
            } catch {
                throw ProfileDecodeFailure(profileID: entity.id, profileName: entity.name, underlying: error)
            }
        }
    }

    private func makeEntity(from profile: MappingProfile) throws -> MappingProfileEntity {
        let payloadData = try encoder.encode(profile.payload)

        return MappingProfileEntity(
            id: profile.id,
            name: profile.name,
            isBuiltIn: profile.isBuiltIn,
            isActive: profile.isActive,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            payloadData: payloadData
        )
    }

    private func makeDomain(from entity: MappingProfileEntity) throws -> MappingProfile {
        let payload = try decoder.decode(MappingProfilePayload.self, from: entity.payloadData)

        return MappingProfile(
            id: entity.id,
            name: entity.name,
            isBuiltIn: entity.isBuiltIn,
            isActive: entity.isActive,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            payload: payload
        )
    }
}
