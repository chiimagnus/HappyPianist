import SwiftUI

struct PracticeRoundSummaryView: View {
    let summary: PracticeRoundSummaryViewModel
    let onRetryHotspot: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack {
            Label(summary.isStable ? "这一轮已经连起来了" : "这一轮练习完成", systemImage: summary.isStable ? "sparkles" : "music.note")
                .bold()
            if let hotspot = summary.hotspot {
                Text("可以再照顾第 \(hotspot.sourceMeasureID.sourceMeasureIndex + 1) 小节")
            }
            HStack {
                if summary.hotspot != nil {
                    Button("重练这个小节", systemImage: "arrow.clockwise", action: onRetryHotspot)
                        .buttonStyle(.borderedProminent)
                }
                Button("继续", systemImage: "forward", action: onContinue)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .glassBackgroundEffect()
    }
}
