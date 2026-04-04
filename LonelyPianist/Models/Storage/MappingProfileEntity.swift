import Foundation
import SwiftData

@Model
final class MappingProfileEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var isBuiltIn: Bool
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.externalStorage) var payloadData: Data

    init(
        id: UUID,
        name: String,
        isBuiltIn: Bool,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date,
        payloadData: Data
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.payloadData = payloadData
    }
}
