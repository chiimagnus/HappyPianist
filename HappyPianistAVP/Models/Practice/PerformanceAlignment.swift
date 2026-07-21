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

enum PerformanceAlignmentNoCandidateReason: String, Codable, Equatable, Sendable {
    case unsupportedObservation
    case staleGeneration
    case outsideActiveRange
    case noTemporalCandidate
    case noPitchCandidate
}

struct PerformanceAlignmentCandidateSnapshot: Codable, Equatable, Sendable {
    let observation: PerformanceAlignmentObservationReference
    let candidates: [PerformanceAlignmentCandidate]
    let noCandidateReason: PerformanceAlignmentNoCandidateReason?
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

struct PerformanceAlignmentControllerScoreReference: Codable, Equatable, Hashable, Sendable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let controllerNumber: UInt8
    let value: UInt8

    init(event: ScorePerformanceControllerEvent) {
        sourceDirectionID = event.sourceDirectionID
        performedOccurrenceIndex = event.performedOccurrenceIndex
        tick = event.tick
        controllerNumber = event.controllerNumber
        value = event.value
    }
}

enum PerformanceAlignmentControllerLink: Codable, Equatable, Sendable {
    case aligned(
        score: PerformanceAlignmentControllerScoreReference,
        observation: PerformanceAlignmentObservationReference,
        timeDeviationSeconds: TimeInterval,
        normalizedValueDeviation: Double
    )
    case missing(score: PerformanceAlignmentControllerScoreReference)
    case extra(observation: PerformanceAlignmentObservationReference)
    case notObserved(score: PerformanceAlignmentControllerScoreReference)
}

struct PerformanceAlignment: Codable, Equatable, Sendable {
    let planID: ScorePerformancePlanID
    let sourceGeneration: UInt64
    let links: [PerformanceAlignmentLink]
    let controllerLinks: [PerformanceAlignmentControllerLink]

    init(
        planID: ScorePerformancePlanID,
        sourceGeneration: UInt64,
        links: [PerformanceAlignmentLink],
        controllerLinks: [PerformanceAlignmentControllerLink] = []
    ) {
        self.planID = planID
        self.sourceGeneration = sourceGeneration
        self.links = links
        self.controllerLinks = controllerLinks
    }
}
