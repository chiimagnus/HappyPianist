struct PracticeRoundSummaryViewModel: Equatable {
    let configuration: PracticeRoundConfiguration
    let isStable: Bool
    let hotspot: PracticeHotspot?
    let nextAction: PracticeNextAction

    init?(
        progress: SongPracticeProgress?,
        configuration: PracticeRoundConfiguration?,
        passageSourceMeasureIDs: Set<PracticeSourceMeasureID>,
        isFullPassage: Bool
    ) {
        guard let progress, let configuration else { return nil }
        self.configuration = configuration
        let facts = progress.measureFacts.filter {
            $0.handMode == configuration.handMode && passageSourceMeasureIDs.contains($0.sourceMeasureID)
        }
        isStable = facts.isEmpty == false && facts.allSatisfy { $0.state == .stable }
        hotspot = PracticeHotspotPolicy().hotspot(in: facts)
        nextAction = PracticeNextActionPolicy().nextAction(for: PracticeFeedbackContext(
            passageFacts: facts,
            configuration: configuration,
            isFullPassage: isFullPassage
        ))
    }


    var actionTitle: String {
        switch nextAction {
        case .retryMeasure: "重练这个小节"
        case .isolateHands: "先用单手练习"
        case .lowerTempo: "放慢一点再练"
        case .keepTempo: "保持速度再来一轮"
        case .expandPassage: "扩大练习片段"
        case .continuePassage: "继续"
        }
    }
}
