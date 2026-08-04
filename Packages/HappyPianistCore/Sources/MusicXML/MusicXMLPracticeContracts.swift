public enum ScoreHand: String, CaseIterable, Codable, Sendable {
    case right
    case left
    case unknown
}

public enum ScoreHandAssignmentProvenance: String, Codable, Equatable, Hashable, Sendable {
    case score
    case user
    case teacher
    case heuristic
    case unresolved
}

public struct ScoreHandAssignment: Codable, Equatable, Hashable, Sendable {
    public let hand: ScoreHand
    public let provenance: ScoreHandAssignmentProvenance
    public let confidence: Double?

    public init(
        hand: ScoreHand,
        provenance: ScoreHandAssignmentProvenance,
        confidence: Double? = nil
    ) {
        self.hand = hand
        self.provenance = provenance
        self.confidence = confidence.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
    }

    public static let unknown = ScoreHandAssignment(hand: .unknown, provenance: .unresolved)
}

public struct PracticeSourceMeasureID: Codable, Equatable, Hashable, Sendable {
    public let partID: String
    public let sourceMeasureIndex: Int
    public let sourceNumberToken: String?

    public init(partID: String, sourceMeasureIndex: Int, sourceNumberToken: String? = nil) {
        self.partID = partID
        self.sourceMeasureIndex = max(0, sourceMeasureIndex)
        self.sourceNumberToken = sourceNumberToken
    }
}

public struct PracticeMeasureOccurrenceID: Codable, Equatable, Hashable, Sendable {
    public let sourceMeasureID: PracticeSourceMeasureID
    public let occurrenceIndex: Int

    public init(sourceMeasureID: PracticeSourceMeasureID, occurrenceIndex: Int) {
        self.sourceMeasureID = sourceMeasureID
        self.occurrenceIndex = max(0, occurrenceIndex)
    }
}

public struct ScorePerformanceTempoEvent: Codable, Equatable, Sendable {
    public let sourceDirectionID: MusicXMLDirectionSourceID?
    public let performedOccurrenceIndex: Int
    public let tick: Int
    public let quarterBPM: Double
    public let endTick: Int?
    public let endQuarterBPM: Double?

    public init(
        sourceDirectionID: MusicXMLDirectionSourceID?,
        performedOccurrenceIndex: Int,
        tick: Int,
        quarterBPM: Double,
        endTick: Int?,
        endQuarterBPM: Double?
    ) {
        self.sourceDirectionID = sourceDirectionID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.quarterBPM = quarterBPM
        self.endTick = endTick
        self.endQuarterBPM = endQuarterBPM
    }
}
