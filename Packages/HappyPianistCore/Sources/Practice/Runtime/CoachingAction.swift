import Foundation
import MusicXML

public enum CoachingActionKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case pitchAccuracy
    case onsetAlignment
    case chordSynchronization
    case durationControl
    case articulationControl
    case voiceBalance
    case dynamicShaping
    case pedalCoordination
    case tempoStability
    case phraseContinuity
    case evidenceCheck
}

public struct CoachingVoiceFocus: Equatable, Hashable, Sendable {
    public let partID: String
    public let staff: Int
    public let voice: Int

    public init(partID: String, staff: Int, voice: Int) {
        self.partID = partID
        self.staff = staff
        self.voice = voice
    }
}

public enum CoachingReferenceUse: String, Equatable, Hashable, Sendable {
    case score
    case manualReplay
}

public enum CoachingCompletionTarget: Equatable, Sendable {
    case dimensionOutcome(
        dimension: PerformanceAssessmentDimension,
        outcome: PracticeEvidenceOutcome
    )
    case evidenceAvailable(dimension: PerformanceAssessmentDimension)
}

public struct CoachingCompletionCondition: Equatable, Sendable {
    public let target: CoachingCompletionTarget

    public init(target: CoachingCompletionTarget) {
        self.target = target
    }
}

public struct CoachingAction: Equatable, Sendable {
    public let kind: CoachingActionKind
    public let scoreRange: Range<Int>
    public let tempoRatio: Double?
    public let handFocus: ScoreHandAssignment?
    public let fingerings: [MusicXMLFingering]
    public let voiceFocus: CoachingVoiceFocus?
    public let repeatCount: Int
    public let referenceUse: CoachingReferenceUse?
    public let completionCondition: CoachingCompletionCondition

    public init(
        kind: CoachingActionKind,
        scoreRange: Range<Int>,
        tempoRatio: Double? = nil,
        handFocus: ScoreHandAssignment? = nil,
        fingerings: [MusicXMLFingering] = [],
        voiceFocus: CoachingVoiceFocus? = nil,
        repeatCount: Int,
        referenceUse: CoachingReferenceUse? = nil,
        completionCondition: CoachingCompletionCondition
    ) {
        self.kind = kind
        self.scoreRange = scoreRange
        self.tempoRatio = tempoRatio.flatMap { ratio in
            ratio.isFinite
                ? min(max(ratio, PracticeRoundConfiguration.supportedTempoRange.lowerBound), 1)
                : nil
        }
        self.handFocus = handFocus
        self.fingerings = fingerings
        self.voiceFocus = voiceFocus
        self.repeatCount = max(1, repeatCount)
        self.referenceUse = referenceUse
        self.completionCondition = completionCondition
    }
}
