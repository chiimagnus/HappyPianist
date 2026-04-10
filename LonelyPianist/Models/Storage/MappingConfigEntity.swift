import Foundation
import SwiftData

@Model
final class MappingConfigEntity {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    @Attribute(.externalStorage) var payloadData: Data

    init(
        id: UUID,
        updatedAt: Date,
        payloadData: Data
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.payloadData = payloadData
    }
}
