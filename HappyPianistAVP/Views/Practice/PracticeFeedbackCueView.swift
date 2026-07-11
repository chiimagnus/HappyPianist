import SwiftUI

struct PracticeFeedbackCueView: View {
    let event: PracticeFeedbackEvent

    var body: some View {
        Label(title, systemImage: systemImage)
            .padding()
            .glassBackgroundEffect()
            .accessibilityLabel(title)
    }

    private var title: String {
        switch event.kind {
        case let .retryInvitation(issue):
            switch issue {
            case .wrongNote: "这个音再试一次"
            case .missedNote: "还有一个音在等你"
            case .incompleteChord: "让和弦一起落下"
            }
        case .measureStable: "这个小节已经点亮"
        case .passageStable: "这一段已经连起来了"
        case .roundSummaryReady: "来看看这一轮"
        }
    }

    private var systemImage: String {
        switch event.kind {
        case .retryInvitation: "arrow.clockwise"
        case .measureStable, .passageStable: "sparkles"
        case .roundSummaryReady: "list.bullet.clipboard"
        }
    }
}
