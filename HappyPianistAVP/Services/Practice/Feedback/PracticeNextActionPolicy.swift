import Foundation

struct PracticeNextActionPolicy {
    private let hotspotPolicy = PracticeHotspotPolicy()

    func nextAction(for context: PracticeFeedbackContext) -> PracticeNextAction {
        if let decision = context.coachingDecision {
            if let tempoRatio = decision.action.tempoRatio,
               tempoRatio < context.configuration.tempoScale
            {
                return .lowerTempo(tempoRatio)
            }
            if let hotspot = hotspotPolicy.hotspot(for: decision) {
                return .retryMeasure(hotspot.sourceMeasureID)
            }
            return .continuePassage
        }

        if let retrySourceMeasureID = basicRetryMeasure(in: context.passageFacts) {
            return .retryMeasure(retrySourceMeasureID)
        }
        guard PracticePassageCoverage.hasStablePitchSteps(
            facts: context.passageFacts,
            sourceMeasureIDs: context.passageSourceMeasureIDs
        ) else {
            return .continuePassage
        }
        return context.isFullPassage ? .keepTempo : .expandPassage
    }

    private func basicRetryMeasure(in facts: [MeasurePracticeFacts]) -> PracticeSourceMeasureID? {
        facts.enumerated().filter { $0.element.recentIssue != nil }.max { lhs, rhs in
            if lhs.element.lastAttemptAt != rhs.element.lastAttemptAt {
                return (lhs.element.lastAttemptAt ?? .distantPast)
                    < (rhs.element.lastAttemptAt ?? .distantPast)
            }
            return lhs.offset < rhs.offset
        }?.element.sourceMeasureID
    }
}
