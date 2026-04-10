import Foundation
@testable import LonelyPianist

@MainActor
final class MappingConfigRepositoryTestDouble: MappingConfigRepositoryProtocol {
    var config: MappingConfig?

    private(set) var ensureSeedCallCount = 0
    private(set) var saveCallCount = 0

    init(config: MappingConfig? = nil) {
        self.config = config
    }

    func ensureSeedConfigIfNeeded() throws {
        ensureSeedCallCount += 1

        guard config == nil else { return }

        config = MappingConfig(
            id: UUID(),
            updatedAt: .now,
            payload: .empty
        )
    }

    func fetchConfig() throws -> MappingConfig {
        if let config {
            return config
        }
        let seeded = MappingConfig(
            id: UUID(),
            updatedAt: .now,
            payload: .empty
        )
        self.config = seeded
        return seeded
    }

    func saveConfig(_ config: MappingConfig) throws {
        saveCallCount += 1
        self.config = config
    }
}
