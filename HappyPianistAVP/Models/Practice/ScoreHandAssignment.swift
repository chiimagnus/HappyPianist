import Foundation

enum ScoreHandAssignmentProvenance: String, Codable, Equatable, Hashable, Sendable {
    case score
    case user
    case teacher
    case heuristic
    case unresolved
}

struct ScoreHandAssignment: Codable, Equatable, Hashable, Sendable {
    let hand: ScoreHand
    let provenance: ScoreHandAssignmentProvenance
    let confidence: Double?

    init(
        hand: ScoreHand,
        provenance: ScoreHandAssignmentProvenance,
        confidence: Double? = nil
    ) {
        self.hand = hand
        self.provenance = provenance
        self.confidence = confidence.map { min(max($0, 0), 1) }
    }

    static let unknown = ScoreHandAssignment(hand: .unknown, provenance: .unresolved)
}
