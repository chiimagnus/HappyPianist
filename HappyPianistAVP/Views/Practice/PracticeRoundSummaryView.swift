import SwiftUI

struct PracticeRoundSummaryView: View {
    let summary: PracticeRoundSummaryViewModel
    let onPrimaryAction: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack {
            Label(summary.isStable ? "这一轮已经连起来了" : "这一轮练习完成", systemImage: summary.isStable ? "sparkles" : "music.note")
                .bold()
            LabeledContent("练习片段", value: summary.passageTitle)
            LabeledContent("练习手", value: summary.configuration.handMode.title)
            LabeledContent("速度") {
                Text(summary.configuration.tempoScale, format: .percent.precision(.fractionLength(0)))
            }
            if let hotspotTitle = summary.hotspotTitle {
                Text("可以再照顾\(hotspotTitle)")
            }
            HStack {
                Button(summary.actionTitle, systemImage: "arrow.clockwise", action: onPrimaryAction)
                    .buttonStyle(.borderedProminent)
                Button("返回曲库", systemImage: "books.vertical", action: onContinue)
            }
        }
        .padding()
        .glassBackgroundEffect()
    }
}
