import Foundation
import MusicXML

public struct PerformanceAssessmentRubricVersion: Equatable, Hashable, Sendable {
    public static let capabilityAware = Self(rawValue: "performance-assessment-v2")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct PerformanceAssessmentEvidenceCoverage: Equatable {
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

public enum PerformanceAssessmentDimension: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
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

    var musicalIssueKind: MusicalIssueKind {
        switch self {
        case .exactPitch, .extraNotes, .missingNotes:
            .pitch
        case .onset:
            .onset
        case .chordSpread:
            .chordSpread
        case .duration, .release:
            .duration
        case .articulation:
            .articulation
        case .velocity, .dynamicContour:
            .dynamicContour
        case .voicing:
            .voicing
        case .pedalTiming, .pedalValue:
            .pedal
        case .tempoRelativeTiming, .tempoContinuity:
            .tempo
        case .phraseContinuity:
            .phrase
        }
    }
}

public enum PerformanceAssessmentEvidenceStatus: String, Codable, Equatable, Hashable, Sendable {
    case observed
    case degraded
    case notObserved
    case insufficient
}

public enum PerformanceAssessmentMeasurementUnit: String, Codable, Equatable, Hashable, Sendable {
    case count
    case ratio
    case seconds
    case normalized
    case midi7Bit
}

public struct PerformanceAssessmentMeasurement: Codable, Equatable, Sendable {
    public let value: Double
    public let unit: PerformanceAssessmentMeasurementUnit

    public init?(value: Double, unit: PerformanceAssessmentMeasurementUnit) {
        guard value.isFinite else { return nil }
        self.value = value
        self.unit = unit
    }
}

enum PerformanceAssessmentEvidenceLink: Equatable {
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

public struct PerformanceAssessmentDimensionResult: Equatable, Sendable {
    public let dimension: PerformanceAssessmentDimension
    public let outcome: PracticeEvidenceOutcome
    public let evidenceStatus: PerformanceAssessmentEvidenceStatus
    public let measurement: PerformanceAssessmentMeasurement?
    public let sampleCount: Int
    public let confidence: Double?
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

extension PerformanceAssessmentDimensionResult {
    static func aggregated(
        _ results: [PerformanceAssessmentDimensionResult]
    ) -> [PerformanceAssessmentDimensionResult] {
        let grouped = Dictionary(grouping: results, by: \.dimension)
        return PerformanceAssessmentDimension.allCases.compactMap { dimension in
            guard let values = grouped[dimension], values.isEmpty == false else { return nil }
            return PerformanceAssessmentDimensionResult(
                dimension: dimension,
                outcome: aggregateOutcome(values.map(\.outcome)),
                evidenceStatus: aggregateEvidenceStatus(values.map(\.evidenceStatus)),
                measurement: aggregateMeasurement(values),
                sampleCount: saturatingSum(values.map(\.sampleCount)),
                confidence: weightedMean(
                    values.compactMap { result in
                        result.confidence.map { ($0, result.sampleCount) }
                    }
                ),
                evidence: values.flatMap(\.evidence)
            )
        }
    }

    private static func aggregateOutcome(
        _ outcomes: [PracticeEvidenceOutcome]
    ) -> PracticeEvidenceOutcome {
        if outcomes.contains(.incorrect) { return .incorrect }
        if outcomes.allSatisfy({ $0 == .correct }) { return .correct }
        return .insufficientEvidence
    }

    private static func aggregateEvidenceStatus(
        _ statuses: [PerformanceAssessmentEvidenceStatus]
    ) -> PerformanceAssessmentEvidenceStatus {
        if statuses.contains(.insufficient) || statuses.contains(.notObserved) { return .insufficient }
        if statuses.contains(.degraded) { return .degraded }
        return statuses.contains(.observed) ? .observed : .notObserved
    }

    private static func aggregateMeasurement(
        _ results: [PerformanceAssessmentDimensionResult]
    ) -> PerformanceAssessmentMeasurement? {
        let measurements = results.compactMap { result in
            result.measurement.map { ($0, result.sampleCount) }
        }
        guard let unit = measurements.first?.0.unit,
              measurements.allSatisfy({ $0.0.unit == unit })
        else { return nil }
        let value: Double?
        if unit == .count {
            let total = measurements.map(\.0.value).reduce(0, +)
            value = total.isFinite ? total : nil
        } else {
            value = weightedMean(measurements.map { ($0.0.value, $0.1) })
        }
        return value.flatMap { PerformanceAssessmentMeasurement(value: $0, unit: unit) }
    }

    private static func weightedMean(_ values: [(value: Double, weight: Int)]) -> Double? {
        let positive = values.filter { $0.weight > 0 }
        let totalWeight = positive.reduce(0.0) { $0 + Double($1.weight) }
        guard totalWeight > 0 else { return nil }
        let total = positive.reduce(0.0) { $0 + ($1.value * Double($1.weight)) }
        guard total.isFinite else { return nil }
        return total / totalWeight
    }

    private static func saturatingSum(_ values: [Int]) -> Int {
        values.reduce(0) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(max(0, value))
            return overflow ? Int.max : sum
        }
    }
}

public struct MeasurePerformanceAssessment: Equatable, Sendable {
    public let occurrenceID: PracticeMeasureOccurrenceID
    public let tickRange: Range<Int>
    public let dimensions: [PerformanceAssessmentDimensionResult]

    var evidenceCoverage: PerformanceAssessmentEvidenceCoverage {
        PerformanceAssessmentEvidenceCoverage(dimensions: dimensions)
    }
}

public struct PassagePerformanceAssessment: Equatable, Sendable {
    public let planID: ScorePerformancePlanID
    public let sourceGeneration: UInt64
    public let tickRange: Range<Int>
    public let rubricVersion: PerformanceAssessmentRubricVersion
    public let dimensions: [PerformanceAssessmentDimensionResult]
    public let measures: [MeasurePerformanceAssessment]

    var evidenceCoverage: PerformanceAssessmentEvidenceCoverage {
        PerformanceAssessmentEvidenceCoverage(dimensions: dimensions)
    }
}
