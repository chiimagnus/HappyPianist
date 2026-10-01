import SwiftUI
import Practice

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
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func icon(for state: MeasurePitchStepLearningState) -> String {
        switch state { case .notStarted: "circle"; case .learning: "circle.lefthalf.filled"; case .pitchStepStable: "checkmark.circle.fill" }
    }

}
