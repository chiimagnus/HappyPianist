import Foundation
import MusicXML

public enum MusicalIssueKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case pitch
    case onset
    case chordSpread
    case duration
    case articulation
    case voicing
    case dynamicContour
    case pedal
    case tempo
    case phrase
    case evidence
}

public struct MusicalIssueProvenance: Equatable, Sendable {
    public let planID: ScorePerformancePlanID
    public let sourceGeneration: UInt64
    public let rubricVersion: PerformanceAssessmentRubricVersion

    public init(
        planID: ScorePerformancePlanID,
        sourceGeneration: UInt64,
        rubricVersion: PerformanceAssessmentRubricVersion
    ) {
        self.planID = planID
        self.sourceGeneration = sourceGeneration
        self.rubricVersion = rubricVersion
    }
}

public struct MusicalIssue: Equatable, Sendable {
    public let kind: MusicalIssueKind
    public let scoreRange: Range<Int>
    public let measureOccurrenceIDs: [PracticeMeasureOccurrenceID]
    public let dimensionResults: [PerformanceAssessmentDimensionResult]
    public let confidence: Double?
    public let provenance: MusicalIssueProvenance

    public init(
        kind: MusicalIssueKind,
        scoreRange: Range<Int>,
        measureOccurrenceIDs: [PracticeMeasureOccurrenceID] = [],
        dimensionResults: [PerformanceAssessmentDimensionResult],
        confidence: Double?,
        provenance: MusicalIssueProvenance
    ) {
        self.kind = kind
        self.scoreRange = scoreRange
        self.measureOccurrenceIDs = measureOccurrenceIDs
        self.dimensionResults = dimensionResults
        self.confidence = confidence.flatMap { value in
            value.isFinite ? min(max(value, 0), 1) : nil
        }
        self.provenance = provenance
    }
}
