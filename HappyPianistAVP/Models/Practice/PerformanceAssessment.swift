import Foundation

struct PerformanceAssessmentRubricVersion: Equatable, Hashable, Sendable {
    static let initial = Self(rawValue: "performance-assessment-v1")
    static let capabilityAware = Self(rawValue: "performance-assessment-v2")

    let rawValue: String
}

struct PerformanceAssessmentEvidenceCoverage: Equatable, Sendable {
    let dimensionCount: Int
    let observedCount: Int
    let degradedCount: Int
    let insufficientCount: Int

    var ratio: Double? {
        guard dimensionCount > 0 else { return nil }
        return Double(observedCount + degradedCount) / Double(dimensionCount)
    }

    init(dimensions: [PerformanceAssessmentDimensionResult]) {
        dimensionCount = dimensions.count
        observedCount = dimensions.count(where: { $0.evidenceStatus == .observed })
        degradedCount = dimensions.count(where: { $0.evidenceStatus == .degraded })
        insufficientCount = dimensions.count(where: { $0.evidenceStatus == .insufficient })
    }
}

enum PerformanceAssessmentDimension: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case exactPitch
    case extraNotes
    case missingNotes
    case onset
    case tempoRelativeTiming
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

enum PerformanceAssessmentEvidenceStatus: String, Codable, Equatable, Hashable, Sendable {
    case observed
    case degraded
    case notObserved
    case insufficient
}

enum PerformanceAssessmentMeasurementUnit: String, Codable, Equatable, Hashable, Sendable {
    case count
    case ratio
    case seconds
    case normalized
    case midi7Bit
}

struct PerformanceAssessmentMeasurement: Codable, Equatable, Sendable {
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
    case ambiguousObservation(observationID: UUID)
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

    var evidenceCoverage: PerformanceAssessmentEvidenceCoverage {
        PerformanceAssessmentEvidenceCoverage(dimensions: dimensions)
    }
}

struct PassagePerformanceAssessment: Equatable, Sendable {
    let planID: ScorePerformancePlanID
    let sourceGeneration: UInt64
    let tickRange: Range<Int>
    let rubricVersion: PerformanceAssessmentRubricVersion
    let dimensions: [PerformanceAssessmentDimensionResult]
    let measures: [MeasurePerformanceAssessment]

    var evidenceCoverage: PerformanceAssessmentEvidenceCoverage {
        PerformanceAssessmentEvidenceCoverage(dimensions: dimensions)
    }
}
