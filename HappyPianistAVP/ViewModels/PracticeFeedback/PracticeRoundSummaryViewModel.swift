struct PracticeRoundSummaryViewModel: Equatable {
    let configuration: PracticeRoundConfiguration
    let isStable: Bool
    let hotspot: PracticeHotspot?
    let nextAction: PracticeNextAction

    init?(
        progress: SongPracticeProgress?,
        configuration: PracticeRoundConfiguration?,
        passageOccurrences: [PracticeMeasureOccurrenceID],
        isFullPassage: Bool
    ) {
        guard let progress,
              let configuration,
              passageOccurrences.isEmpty == false
        else { return nil }
        self.configuration = configuration
        passageTitle = Self.passageTitle(for: passageOccurrences)
        let passageSourceMeasureIDs = Set(passageOccurrences.map(\.sourceMeasureID))
        let facts = progress.measureFacts.filter {
            $0.handMode == configuration.handMode && passageSourceMeasureIDs.contains($0.sourceMeasureID)
        }
        isStable = PracticePassageCoverage.isStable(
            facts: facts,
            sourceMeasureIDs: passageSourceMeasureIDs
        )
        hotspot = PracticeHotspotPolicy().hotspot(in: facts)
        nextAction = PracticeNextActionPolicy().nextAction(for: PracticeFeedbackContext(
            passageFacts: facts,
            passageSourceMeasureIDs: passageSourceMeasureIDs,
            configuration: configuration,
            isFullPassage: isFullPassage
        ))
    }


    var actionTitle: String {
        switch nextAction {
        case .retryMeasure: "重练这个小节"
        case .lowerTempo: "放慢一点再练"
        case .keepTempo: "保持速度再来一轮"
        case .expandPassage: "扩大练习片段"
        case .continuePassage: "继续"
        }
    }

    let passageTitle: String

    private static func passageTitle(for occurrences: [PracticeMeasureOccurrenceID]) -> String {
        guard let first = occurrences.first, let last = occurrences.last else { return "" }
        let start = measureTitle(first.sourceMeasureID)
        let end = measureTitle(last.sourceMeasureID)
        guard first != last else { return "第 \(start) 小节" }
        let crossesRepeat = zip(occurrences, occurrences.dropFirst()).contains { previous, next in
            next.sourceMeasureID.sourceMeasureIndex <= previous.sourceMeasureID.sourceMeasureIndex
        }
        return crossesRepeat
            ? "第 \(start) 小节至重复后的第 \(end) 小节"
            : "第 \(start)–\(end) 小节"
    }

    var hotspotTitle: String? {
        hotspot.map { "第 \(Self.measureTitle($0.sourceMeasureID)) 小节" }
    }

    private static func measureTitle(_ id: PracticeSourceMeasureID) -> String {
        id.sourceNumberToken ?? "\(id.sourceMeasureIndex + 1)"
    }
}
