import SwiftUI

struct ImmersiveNotationPanelView: View {
    @Bindable var sessionViewModel: PracticeSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Grand Staff 五线谱")
                    .font(.headline)
                Spacer()
                if let currentGuide = sessionViewModel.currentPianoHighlightGuide {
                    Text("tick \(currentGuide.tick)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            GrandStaffNotationView(
                guides: sessionViewModel.highlightGuides,
                currentGuide: sessionViewModel.currentPianoHighlightGuide,
                measureSpans: sessionViewModel.notationMeasureSpans,
                context: sessionViewModel.currentGrandStaffNotationContext,
                scrollTickProvider: sessionViewModel.autoplayState == .playing ? {
                    sessionViewModel.smoothNotationScrollTick()
                } : nil
            )
            .frame(width: 760, height: 260)
        }
        .padding(18)
        .frame(width: 820)
        .glassBackgroundEffect()
    }
}
