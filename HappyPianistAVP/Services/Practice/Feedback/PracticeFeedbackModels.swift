import Foundation

struct PracticeHotspot: Equatable {
    let sourceMeasureID: PracticeSourceMeasureID
    let failedAttempts: Int
}

enum PracticeNextAction: Equatable {
    case retryMeasure(PracticeSourceMeasureID)
    case lowerTempo(Double)
    case keepTempo
    case expandPassage
    case continuePassage
}

struct PracticeFeedbackContext: Equatable {
    let passageFacts: [MeasurePracticeFacts]
    let passageSourceMeasureIDs: Set<PracticeSourceMeasureID>
    let configuration: PracticeRoundConfiguration
    let isFullPassage: Bool
}

enum PracticePassageCoverage {
    static func isStable(
        facts: [MeasurePracticeFacts],
        sourceMeasureIDs: Set<PracticeSourceMeasureID>
    ) -> Bool {
        guard sourceMeasureIDs.isEmpty == false else { return false }
        let stableIDs = Set(facts.lazy.filter { $0.state == .stable }.map(\.sourceMeasureID))
        return sourceMeasureIDs.isSubset(of: stableIDs)
    }
}
