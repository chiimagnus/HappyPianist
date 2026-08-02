import Foundation
import MusicXML

public enum PerformanceAlignmentEvidenceDimension: String, Codable, Equatable, Hashable, Sendable {
    case pitch
    case onset
    case chordSpread
    case release
    case duration
    case voice
    case occurrence
    case hand
    case controller
    case velocity
    case confidence
}

public enum PerformanceAlignmentEvidenceStatus: String, Codable, Equatable, Hashable, Sendable {
    case observed
    case degraded
    case notObserved
}

public struct PerformanceAlignmentEvidence: Codable, Equatable, Sendable {
    public let dimension: PerformanceAlignmentEvidenceDimension
    public let status: PerformanceAlignmentEvidenceStatus
    public let cost: Double?
    public let deviationSeconds: TimeInterval?

    public init(
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

public struct PerformanceAlignmentScoreReference: Codable, Equatable, Hashable, Sendable {
    public let eventID: ScorePerformanceNoteEventID
    public let sourceNoteID: MusicXMLSourceNoteID
    public let performedOccurrenceIndex: Int
    public let performedOnTick: Int

    public init(event: ScorePerformanceNoteEvent) {
        eventID = event.id
        sourceNoteID = event.sourceNoteID
        performedOccurrenceIndex = event.performedOccurrenceIndex
        performedOnTick = event.performedOnTick
    }
}

public struct PerformanceAlignmentObservationReference: Codable, Equatable, Sendable {
    public let observationID: UUID
    public let source: PerformanceObservation.Source
    public let correctedTime: PerformanceMonotonicInstant
    public let hand: ScoreHand?
    public let finger: Int?
    public let onsetVelocity: PerformanceObservation.NormalizedValue?
    public let confidence: Double?
    public let calibrationReference: String?

    public init(observation: PerformanceObservation) {
        observationID = observation.id
        source = observation.source
        correctedTime = observation.alignmentTimestamp
        hand = observation.hand
        finger = observation.finger
        onsetVelocity = observation.onsetVelocity
        confidence = observation.confidence
        calibrationReference = observation.calibrationReference
    }
}

public struct PerformanceAlignmentCandidate: Codable, Equatable, Sendable {
    public let score: PerformanceAlignmentScoreReference
    public let totalCost: Double
    public let evidence: [PerformanceAlignmentEvidence]

    public init(
        score: PerformanceAlignmentScoreReference,
        totalCost: Double,
        evidence: [PerformanceAlignmentEvidence]
    ) {
        self.score = score
        self.totalCost = totalCost.isFinite ? max(0, totalCost) : .greatestFiniteMagnitude
        self.evidence = evidence
    }
}

public enum PerformanceAlignmentNoCandidateReason: String, Codable, Equatable, Sendable {
    case unsupportedObservation
    case staleGeneration
    case outsideActiveRange
    case noTemporalCandidate
    case noPitchCandidate
    case noHandCandidate
}

public struct PerformanceAlignmentCandidateSnapshot: Codable, Equatable, Sendable {
    public let observation: PerformanceAlignmentObservationReference
    public let candidates: [PerformanceAlignmentCandidate]
    public let noCandidateReason: PerformanceAlignmentNoCandidateReason?

    public init(
        observation: PerformanceAlignmentObservationReference,
        candidates: [PerformanceAlignmentCandidate],
        noCandidateReason: PerformanceAlignmentNoCandidateReason?
    ) {
        self.observation = observation
        self.candidates = candidates
        self.noCandidateReason = noCandidateReason
    }
}

public enum PerformanceAlignmentLink: Codable, Equatable, Sendable {
    case aligned(
        score: PerformanceAlignmentScoreReference,
        observation: PerformanceAlignmentObservationReference,
        evidence: [PerformanceAlignmentEvidence]
    )
    case missing(score: PerformanceAlignmentScoreReference, evidence: [PerformanceAlignmentEvidence])
    case extra(
        observation: PerformanceAlignmentObservationReference,
        evidence: [PerformanceAlignmentEvidence],
        noCandidateReason: PerformanceAlignmentNoCandidateReason?
    )
    case ambiguous(
        observation: PerformanceAlignmentObservationReference,
        candidates: [PerformanceAlignmentCandidate]
    )
    case provisional(
        score: PerformanceAlignmentScoreReference,
        observation: PerformanceAlignmentObservationReference,
        candidates: [PerformanceAlignmentCandidate]
    )
    case unknown(
        observation: PerformanceAlignmentObservationReference,
        reason: PerformanceAlignmentUnknownReason
    )
}

public enum PerformanceAlignmentUnknownReason: String, Codable, Equatable, Sendable {
    case unavailablePitchEvidence
    case ambiguousKeyCandidate
    case aggregateAudioEvidence
    case unsupportedObservation
}

public struct PerformanceAlignmentControllerScoreReference: Codable, Equatable, Hashable, Sendable {
    public let sourceDirectionID: MusicXMLDirectionSourceID?
    public let performedOccurrenceIndex: Int
    public let tick: Int
    public let controllerNumber: UInt8
    public let value: UInt8

    public init(event: ScorePerformanceControllerEvent) {
        sourceDirectionID = event.sourceDirectionID
        performedOccurrenceIndex = event.performedOccurrenceIndex
        tick = event.tick
        controllerNumber = event.controllerNumber
        value = event.value
    }
}

public enum PerformanceAlignmentControllerLink: Codable, Equatable, Sendable {
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

public struct PerformanceAlignment: Codable, Equatable, Sendable {
    public let planID: ScorePerformancePlanID
    public let sourceGeneration: UInt64
    public let links: [PerformanceAlignmentLink]
    public let controllerLinks: [PerformanceAlignmentControllerLink]

    public init(
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
