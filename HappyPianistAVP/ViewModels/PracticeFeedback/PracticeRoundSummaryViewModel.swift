struct PracticeRoundSummaryViewModel: Equatable {
    let configuration: PracticeRoundConfiguration
    let isStable: Bool
    let hotspot: PracticeHotspot?
    let nextAction: PracticeNextAction

    init?(progress: SongPracticeProgress?, configuration: PracticeRoundConfiguration?, isFullPassage: Bool) {
        guard let progress, let configuration else { return nil }
        self.configuration = configuration
        let facts = progress.measureFacts.filter { $0.handMode == configuration.handMode }
        isStable = facts.isEmpty == false && facts.allSatisfy { $0.state == .stable }
        hotspot = PracticeHotspotPolicy().hotspot(in: facts)
        nextAction = PracticeNextActionPolicy().nextAction(for: PracticeFeedbackContext(
            passageFacts: facts,
            configuration: configuration,
            isFullPassage: isFullPassage
        ))
    }
}
