import Foundation

struct PerformanceAssessmentRubricVersion: Equatable, Hashable, Sendable {
    static let initial = Self(rawValue: "performance-assessment-v1")

    let rawValue: String
}

enum PerformanceAssessmentDimension: String, CaseIterable, Equatable, Hashable, Sendable {
    case exactPitch
    case extraNotes
    case missingNotes
    case onset
    case chordSpread
    case duration
    case release
    case articulation
    case velocity
    case dynamicContour
    case voicing
    case pedalTiming
    case pedalValue
    case tempoContinuity
    case phraseContinuity
}

enum PerformanceAssessmentEvidenceStatus: String, Equatable, Hashable, Sendable {
    case observed
    case degraded
    case notObserved
    case insufficient
}

enum PerformanceAssessmentMeasurementUnit: String, Equatable, Hashable, Sendable {
    case count
    case ratio
    case seconds
    case normalized
    case midi7Bit
}

struct PerformanceAssessmentMeasurement: Equatable, Sendable {
    let value: Double
    let unit: PerformanceAssessmentMeasurementUnit

    init?(value: Double, unit: PerformanceAssessmentMeasurementUnit) {
        guard value.isFinite else { return nil }
        self.value = value
        self.unit = unit
    }
}

enum PerformanceAssessmentEvidenceLink: Equatable, Sendable {
    case note(
        score: PerformanceAlignmentScoreReference,
        observationID: UUID?,
        dimension: PerformanceAlignmentEvidenceDimension
    )
    case controller(
        score: PerformanceAlignmentControllerScoreReference,
        observationID: UUID?
    )
    case unmatchedObservation(observationID: UUID)
    case unknownObservation(observationID: UUID, reason: PerformanceAlignmentUnknownReason)
}

struct PerformanceAssessmentDimensionResult: Equatable, Sendable {
    let dimension: PerformanceAssessmentDimension
    let outcome: PracticeEvidenceOutcome
    let evidenceStatus: PerformanceAssessmentEvidenceStatus
    let measurement: PerformanceAssessmentMeasurement?
    let sampleCount: Int
    let confidence: Double?
    let evidence: [PerformanceAssessmentEvidenceLink]

    init(
        dimension: PerformanceAssessmentDimension,
        outcome: PracticeEvidenceOutcome,
        evidenceStatus: PerformanceAssessmentEvidenceStatus,
        measurement: PerformanceAssessmentMeasurement? = nil,
        sampleCount: Int,
        confidence: Double? = nil,
        evidence: [PerformanceAssessmentEvidenceLink]
    ) {
        self.dimension = dimension
        self.outcome = outcome
        self.evidenceStatus = evidenceStatus
        self.measurement = measurement
        self.sampleCount = max(0, sampleCount)
        self.confidence = confidence.flatMap { value in
            value.isFinite ? min(max(value, 0), 1) : nil
        }
        self.evidence = evidence
    }
}

struct MeasurePerformanceAssessment: Equatable, Sendable {
    let occurrenceID: PracticeMeasureOccurrenceID
    let tickRange: Range<Int>
    let dimensions: [PerformanceAssessmentDimensionResult]
}

struct PassagePerformanceAssessment: Equatable, Sendable {
    let planID: ScorePerformancePlanID
    let sourceGeneration: UInt64
    let tickRange: Range<Int>
    let rubricVersion: PerformanceAssessmentRubricVersion
    let dimensions: [PerformanceAssessmentDimensionResult]
    let measures: [MeasurePerformanceAssessment]
}
