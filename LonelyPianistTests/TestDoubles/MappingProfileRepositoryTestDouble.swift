import Foundation
@testable import LonelyPianist

@MainActor
final class MappingProfileRepositoryTestDouble: MappingProfileRepositoryProtocol {
    var profiles: [MappingProfile]

    private(set) var ensureSeedCallCount = 0
    private(set) var saveCallCount = 0

    init(profiles: [MappingProfile] = []) {
        self.profiles = profiles
    }

    func ensureSeedProfilesIfNeeded() throws {
        ensureSeedCallCount += 1

        guard profiles.isEmpty else { return }

        let seeded = MappingProfile(
            id: UUID(),
            name: "Seeded",
            isBuiltIn: false,
            isActive: true,
            createdAt: .now,
            updatedAt: .now,
            payload: .empty
        )
        profiles = [seeded]
    }

    func fetchProfiles() throws -> [MappingProfile] {
        profiles
    }

    func saveProfile(_ profile: MappingProfile) throws {
        saveCallCount += 1

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    func deleteProfile(id: UUID) throws {
        profiles.removeAll { $0.id == id }
    }

    func setActiveProfile(id: UUID) throws {
        for index in profiles.indices {
            profiles[index].isActive = profiles[index].id == id
        }
    }
}
