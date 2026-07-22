import Foundation

struct PracticeRoundSummaryViewModel: Equatable {
    let configuration: PracticeRoundConfiguration
    let hasStablePitchSteps: Bool
    let hotspot: PracticeHotspot?
    let nextAction: PracticeNextAction
    let coachingPresentation: PracticeCoachingPresentation?

    init?(
        progress: SongPracticeProgress?,
        configuration: PracticeRoundConfiguration?,
        passageOccurrences: [PracticeMeasureOccurrenceID],
        isFullPassage: Bool,
        coachingDecision: CoachingDecision? = nil
    ) {
        guard let progress,
              let configuration,
              passageOccurrences.isEmpty == false
        else { return nil }
        self.configuration = configuration
        passageTitle = PracticePassagePresentation.title(for: passageOccurrences)
        let passageSourceMeasureIDs = Set(passageOccurrences.map(\.sourceMeasureID))
        let facts = progress.measureFacts.filter {
            $0.handMode == configuration.handMode && passageSourceMeasureIDs.contains($0.sourceMeasureID)
        }
        hasStablePitchSteps = PracticePassageCoverage.hasStablePitchSteps(
            facts: facts,
            sourceMeasureIDs: passageSourceMeasureIDs
        )
        let feedbackContext = PracticeFeedbackContext(
            passageFacts: facts,
            passageSourceMeasureIDs: passageSourceMeasureIDs,
            configuration: configuration,
            isFullPassage: isFullPassage,
            coachingDecision: coachingDecision
        )
        hotspot = PracticeHotspotPolicy().hotspot(for: coachingDecision)
        nextAction = PracticeNextActionPolicy().nextAction(for: feedbackContext)
        coachingPresentation = coachingDecision.map(PracticeCoachingPresentation.init)
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

    var detailText: String {
        var lines = [
            "练习片段：\(passageTitle)",
            "练习手：\(configuration.handMode.title)",
            "速度：\(configuration.tempoScale.formatted(.percent.precision(.fractionLength(0))))",
        ]
        if let hotspotTitle {
            lines.append("可以再照顾\(hotspotTitle)")
        }
        if let coachingPresentation {
            lines.append("下一步：\(coachingPresentation.actionLabel)")
            if let fingeringText = coachingPresentation.fingeringText {
                lines.append("指法：\(fingeringText)")
            }
            if let sourceLabel = coachingPresentation.sourceLabel {
                lines.append(sourceLabel)
            }
        }
        return lines.joined(separator: "\n")
    }

    let passageTitle: String

    var hotspotTitle: String? {
        hotspot.map { "第 \(PracticePassagePresentation.measureTitle($0.sourceMeasureID)) 小节" }
    }
}
