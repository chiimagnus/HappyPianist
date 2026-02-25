import Foundation

struct MappingProfilePayload: Codable, Hashable, Sendable {
    var velocityEnabled: Bool
    var defaultVelocityThreshold: Int
    var singleKeyRules: [SingleKeyMappingRule]
    var chordRules: [ChordMappingRule]
    var melodyRules: [MelodyMappingRule]

    static let empty = MappingProfilePayload(
        velocityEnabled: false,
        defaultVelocityThreshold: 90,
        singleKeyRules: [],
        chordRules: [],
        melodyRules: []
    )
}

struct MappingProfile: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var payload: MappingProfilePayload
}
