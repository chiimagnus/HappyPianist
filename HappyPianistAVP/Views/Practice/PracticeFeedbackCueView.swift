import SwiftUI

struct PracticeFeedbackCueView: View {
    let event: PracticeFeedbackEvent

    var body: some View {
        let presentation = PracticeFeedbackCuePresentation(event: event)
        Label(presentation.title, systemImage: presentation.systemImage)
            .padding()
            .glassBackgroundEffect()
            .accessibilityLabel(presentation.title)
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
