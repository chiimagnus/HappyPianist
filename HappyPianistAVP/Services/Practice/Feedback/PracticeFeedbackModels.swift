import Foundation

struct PracticeHotspot: Equatable {
    let sourceMeasureID: PracticeSourceMeasureID
}

enum PracticeNextAction: Equatable {
    case retryMeasure(PracticeSourceMeasureID)
    case lowerTempo(Double)
    case keepTempo
    case expandPassage
    case continuePassage
}

struct CoachingDecision: Equatable, Sendable {
    let issue: MusicalIssue
    let action: CoachingAction
}

struct PracticeCoachingPresentation: Equatable, Sendable {
    let actionLabel: String
    let sourceLabel: String?
    let fingeringText: String?
}

struct PracticeFeedbackContext: Equatable {
    let passageFacts: [MeasurePracticeFacts]
    let passageSourceMeasureIDs: Set<PracticeSourceMeasureID>
    let configuration: PracticeRoundConfiguration
    let isFullPassage: Bool
    let coachingDecision: CoachingDecision?

    init(
        passageFacts: [MeasurePracticeFacts],
        passageSourceMeasureIDs: Set<PracticeSourceMeasureID>,
        configuration: PracticeRoundConfiguration,
        isFullPassage: Bool,
        coachingDecision: CoachingDecision? = nil
    ) {
        self.passageFacts = passageFacts
        self.passageSourceMeasureIDs = passageSourceMeasureIDs
        self.configuration = configuration
        self.isFullPassage = isFullPassage
        self.coachingDecision = coachingDecision
    }
}

enum PracticePassageCoverage {
    static func hasStablePitchSteps(
        facts: [MeasurePracticeFacts],
        sourceMeasureIDs: Set<PracticeSourceMeasureID>
    ) -> Bool {
        guard sourceMeasureIDs.isEmpty == false else { return false }
        let stableIDs = Set(facts.lazy.filter { $0.state == .pitchStepStable }.map(\.sourceMeasureID))
        return sourceMeasureIDs.isSubset(of: stableIDs)
    }
}
