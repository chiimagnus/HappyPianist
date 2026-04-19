import Foundation

struct StoredWorldAnchorCalibration: Codable, Equatable {
    let a0AnchorID: UUID
    let c8AnchorID: UUID
    let whiteKeyWidth: Float
    let generatedAt: Date

    init(
        a0AnchorID: UUID,
        c8AnchorID: UUID,
        whiteKeyWidth: Float = 0.0235,
        generatedAt: Date = .now
    ) {
        self.a0AnchorID = a0AnchorID
        self.c8AnchorID = c8AnchorID
        self.whiteKeyWidth = whiteKeyWidth
        self.generatedAt = generatedAt
    }
}
