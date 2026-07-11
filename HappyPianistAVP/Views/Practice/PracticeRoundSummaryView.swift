import SwiftUI

struct PracticeRoundSummaryView: View {
    let summary: PracticeRoundSummaryViewModel
    let onPrimaryAction: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack {
            Label(summary.isStable ? "这一轮已经连起来了" : "这一轮练习完成", systemImage: summary.isStable ? "sparkles" : "music.note")
                .bold()
            if let hotspot = summary.hotspot {
                Text("可以再照顾第 \(hotspot.sourceMeasureID.sourceMeasureIndex + 1) 小节")
            }
            HStack {
                Button(summary.actionTitle, systemImage: "arrow.clockwise", action: onPrimaryAction)
                    .buttonStyle(.borderedProminent)
                Button("返回曲库", systemImage: "books.vertical", action: onContinue)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .glassBackgroundEffect()
    }
}
