import Foundation

@MainActor
protocol MappingConfigRepositoryProtocol {
    func ensureSeedConfigIfNeeded() throws
    func fetchConfig() throws -> MappingConfig
    func saveConfig(_ config: MappingConfig) throws
}
