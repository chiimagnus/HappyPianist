import Foundation

enum PerformanceAlignmentEvidenceDimension: String, Codable, Equatable, Hashable, Sendable {
    case pitch
    case onset
    case chordSpread
    case release
    case duration
    case voice
    case occurrence
    case hand
    case controller
    case confidence
}

enum PerformanceAlignmentEvidenceStatus: String, Codable, Equatable, Hashable, Sendable {
    case observed
    case degraded
    case notObserved
}

struct PerformanceAlignmentEvidence: Codable, Equatable, Sendable {
    let dimension: PerformanceAlignmentEvidenceDimension
    let status: PerformanceAlignmentEvidenceStatus
    let cost: Double?
    let deviationSeconds: TimeInterval?

    init(
        dimension: PerformanceAlignmentEvidenceDimension,
        status: PerformanceAlignmentEvidenceStatus,
        cost: Double? = nil,
        deviationSeconds: TimeInterval? = nil
    ) {
        self.dimension = dimension
        self.status = status
        self.cost = cost.flatMap { $0.isFinite ? max(0, $0) : nil }
        self.deviationSeconds = deviationSeconds.flatMap { $0.isFinite ? $0 : nil }
    }
}

struct PerformanceAlignmentScoreReference: Codable, Equatable, Hashable, Sendable {
    let eventID: ScorePerformanceNoteEventID
    let sourceNoteID: MusicXMLSourceNoteID
    let performedOccurrenceIndex: Int

    init(event: ScorePerformanceNoteEvent) {
        eventID = event.id
        sourceNoteID = event.sourceNoteID
        performedOccurrenceIndex = event.performedOccurrenceIndex
    }
}

struct PerformanceAlignmentObservationReference: Codable, Equatable, Sendable {
    let observationID: UUID
    let source: PerformanceObservation.Source
    let correctedTime: PerformanceMonotonicInstant

    init(observation: PerformanceObservation) {
        observationID = observation.id
        source = observation.source
        correctedTime = observation.alignmentTimestamp
    }
}

struct PerformanceAlignmentCandidate: Codable, Equatable, Sendable {
    let score: PerformanceAlignmentScoreReference
    let totalCost: Double
    let evidence: [PerformanceAlignmentEvidence]

    init(
        score: PerformanceAlignmentScoreReference,
        totalCost: Double,
        evidence: [PerformanceAlignmentEvidence]
    ) {
        self.score = score
        self.totalCost = totalCost.isFinite ? max(0, totalCost) : .greatestFiniteMagnitude
        self.evidence = evidence
    }
}

enum PerformanceAlignmentLink: Codable, Equatable, Sendable {
    case aligned(
        score: PerformanceAlignmentScoreReference,
        observation: PerformanceAlignmentObservationReference,
        evidence: [PerformanceAlignmentEvidence]
    )
    case missing(score: PerformanceAlignmentScoreReference, evidence: [PerformanceAlignmentEvidence])
    case extra(observation: PerformanceAlignmentObservationReference, evidence: [PerformanceAlignmentEvidence])
    case ambiguous(
        observation: PerformanceAlignmentObservationReference,
        candidates: [PerformanceAlignmentCandidate]
    )
    case provisional(
        score: PerformanceAlignmentScoreReference,
        observation: PerformanceAlignmentObservationReference,
        candidates: [PerformanceAlignmentCandidate]
    )
}

struct PerformanceAlignment: Codable, Equatable, Sendable {
    let planID: ScorePerformancePlanID
    let sourceGeneration: UInt64
    let links: [PerformanceAlignmentLink]
}
