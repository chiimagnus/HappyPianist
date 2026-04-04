import Foundation

@MainActor
protocol MappingProfileRepositoryProtocol {
    func ensureSeedProfilesIfNeeded() throws
    func fetchProfiles() throws -> [MappingProfile]
    func saveProfile(_ profile: MappingProfile) throws
    func deleteProfile(id: UUID) throws
    func setActiveProfile(id: UUID) throws
}
