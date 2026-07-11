struct PracticeNextActionPolicy {
    private let hotspotPolicy = PracticeHotspotPolicy()

    func nextAction(for context: PracticeFeedbackContext) -> PracticeNextAction {
        guard let hotspot = hotspotPolicy.hotspot(in: context.passageFacts) else {
            let attempted = context.passageFacts.filter { $0.state != .notStarted }
            guard attempted.isEmpty == false, attempted.allSatisfy({ $0.state == .stable }) else {
                return .continuePassage
            }
            return context.isFullPassage ? .keepTempo : .expandPassage
        }

        if hotspot.handMode == .both, hotspot.failedAttempts >= 2 {
            return .isolateHands(hotspot.sourceMeasureID)
        }
        if hotspot.failedAttempts >= 2,
           context.configuration.tempoScale > PracticeRoundConfiguration.supportedTempoRange.lowerBound
        {
            return .lowerTempo(max(
                PracticeRoundConfiguration.supportedTempoRange.lowerBound,
                context.configuration.tempoScale - 0.1
            ))
        }
        return .retryMeasure(hotspot.sourceMeasureID)
    }
}
