import SwiftUI

struct PracticeMeasureMapView: View {
    let viewModel: PracticeMeasureMapViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(viewModel.items) { item in
                    VStack {
                        Label(item.displayNumber, systemImage: icon(for: item.state))
                            .labelStyle(.titleAndIcon)
                        if item.isHotspot {
                            Label("卡点", systemImage: "scope")
                                .font(.caption)
                        }
                    }
                    .padding(6)
                    .background(item.isCurrentPassage ? .thinMaterial : .regularMaterial, in: .rect(cornerRadius: 8))
                    .overlay { if item.isCurrentMeasure { RoundedRectangle(cornerRadius: 8).stroke(.primary) } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("第 \(item.displayNumber) 小节，\(label(for: item.state))\(item.isHotspot ? "，建议重练" : "")")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func icon(for state: MeasurePitchStepLearningState) -> String {
        switch state { case .notStarted: "circle"; case .learning: "circle.lefthalf.filled"; case .pitchStepStable: "checkmark.circle.fill" }
    }

    private func label(for state: MeasurePitchStepLearningState) -> String {
        switch state { case .notStarted: "尚未开始"; case .learning: "正在练习"; case .pitchStepStable: "音符步骤已稳定" }
    }
}
