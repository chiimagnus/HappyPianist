import Foundation

struct MappingConfigPayload: Codable, Hashable, Sendable {
    var velocityEnabled: Bool
    var defaultVelocityThreshold: Int
    var singleKeyRules: [SingleKeyMappingRule]
    var chordRules: [ChordMappingRule]

    static let empty = MappingConfigPayload(
        velocityEnabled: false,
        defaultVelocityThreshold: 90,
        singleKeyRules: [],
        chordRules: []
    )
}

struct MappingConfig: Identifiable, Hashable, Sendable {
    var id: UUID
    var updatedAt: Date
    var payload: MappingConfigPayload
}
