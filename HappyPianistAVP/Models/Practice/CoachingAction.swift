import Foundation
import MusicXML

enum CoachingActionKind: String, CaseIterable, Equatable, Hashable {
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

struct CoachingVoiceFocus: Equatable, Hashable {
    let partID: String
    let staff: Int
    let voice: Int
}

enum CoachingReferenceUse: String, Equatable, Hashable {
    case score
    case manualReplay
}

enum CoachingCompletionTarget: Equatable {
    case dimensionOutcome(
        dimension: PerformanceAssessmentDimension,
        outcome: PracticeEvidenceOutcome
    )
    case evidenceAvailable(dimension: PerformanceAssessmentDimension)
}

struct CoachingCompletionCondition: Equatable {
    let target: CoachingCompletionTarget
}

struct CoachingAction: Equatable {
    let kind: CoachingActionKind
    let scoreRange: Range<Int>
    let tempoRatio: Double?
    let handFocus: ScoreHandAssignment?
    let fingerings: [MusicXMLFingering]
    let voiceFocus: CoachingVoiceFocus?
    let repeatCount: Int
    let referenceUse: CoachingReferenceUse?
    let completionCondition: CoachingCompletionCondition

    init(
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
