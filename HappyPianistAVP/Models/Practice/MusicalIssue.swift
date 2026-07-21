import Foundation

enum MusicalIssueKind: String, CaseIterable, Equatable, Hashable, Sendable {
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

struct MusicalIssueProvenance: Equatable, Sendable {
    let planID: ScorePerformancePlanID
    let sourceGeneration: UInt64
    let rubricVersion: PerformanceAssessmentRubricVersion
}

struct MusicalIssue: Equatable, Sendable {
    let kind: MusicalIssueKind
    let scoreRange: Range<Int>
    let measureOccurrenceIDs: [PracticeMeasureOccurrenceID]
    let dimensionResults: [PerformanceAssessmentDimensionResult]
    let confidence: Double?
    let provenance: MusicalIssueProvenance

    init(
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
