import Foundation

enum ScoreHandAssignmentProvenance: String, Codable, Equatable, Hashable {
    case score
    case user
    case teacher
    case heuristic
    case unresolved
}

struct ScoreHandAssignment: Codable, Equatable, Hashable {
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
        self.confidence = confidence.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
    }

    static let unknown = ScoreHandAssignment(hand: .unknown, provenance: .unresolved)
}
