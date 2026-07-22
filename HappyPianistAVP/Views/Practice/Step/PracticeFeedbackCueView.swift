import SwiftUI

struct PracticeFeedbackCueView: View {
    let event: PracticeFeedbackEvent
    let coachingPresentation: PracticeCoachingPresentation?

    init(
        event: PracticeFeedbackEvent,
        coachingPresentation: PracticeCoachingPresentation? = nil
    ) {
        self.event = event
        self.coachingPresentation = coachingPresentation
    }

    var body: some View {
        let presentation = PracticeFeedbackCuePresentation(event: event)
        VStack(alignment: .leading) {
            Label(presentation.title, systemImage: presentation.systemImage)
            if let coachingPresentation {
                Text(coachingPresentation.actionLabel)
                    .font(.caption)
                if let fingeringText = coachingPresentation.fingeringText {
                    Text("指法 \(fingeringText)")
                        .font(.caption)
                }
                if let sourceLabel = coachingPresentation.sourceLabel {
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
            .padding()
            .glassBackgroundEffect()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: presentation))
    }

    private func accessibilityLabel(for presentation: PracticeFeedbackCuePresentation) -> String {
        [
            presentation.title,
            coachingPresentation?.actionLabel,
            coachingPresentation?.fingeringText.map { "指法 \($0)" },
            coachingPresentation?.sourceLabel,
        ].compactMap { $0 }.joined(separator: "，")
    }
}

struct PracticeFeedbackCuePresentation: Equatable {
    let title: String
    let systemImage: String

    init(event: PracticeFeedbackEvent) {
        let message = switch event.kind {
        case let .retryInvitation(issue):
            switch issue {
            case .wrongNote: "这个音再试一次"
            case .missedNote: "还有一个音在等你"
            case .incompleteChord: "让和弦一起落下"
            }
        case .measurePitchStepsStable: "这个小节的音符步骤已稳定"
        case .passagePitchStepsStable: "这一段的音符步骤已稳定"
        case .roundSummaryReady: "来看看这一轮"
        }
        if let id = event.sourceMeasureID {
            title = "第 \(id.sourceNumberToken ?? "\(id.sourceMeasureIndex + 1)") 小节：\(message)"
        } else {
            title = message
        }
        systemImage = switch event.kind {
        case .retryInvitation: "arrow.clockwise"
        case .measurePitchStepsStable, .passagePitchStepsStable: "sparkles"
        case .roundSummaryReady: "list.bullet.clipboard"
        }
    }
}
