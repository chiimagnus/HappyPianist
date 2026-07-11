import Foundation

struct PracticeHotspot: Equatable, Sendable {
    let sourceMeasureID: PracticeSourceMeasureID
    let handMode: PracticeHandMode
    let issue: PracticeIssueKind
    let failedAttempts: Int
}

enum PracticeNextAction: Equatable, Sendable {
    case retryMeasure(PracticeSourceMeasureID)
    case isolateHands(PracticeSourceMeasureID)
    case lowerTempo(Double)
    case keepTempo
    case restoreFullPassage
    case expandPassage
    case continuePassage
}

struct PracticeFeedbackContext: Equatable, Sendable {
    let passageFacts: [MeasurePracticeFacts]
    let configuration: PracticeRoundConfiguration
    let isFullPassage: Bool
}
