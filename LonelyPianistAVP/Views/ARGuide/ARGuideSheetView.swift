import SwiftUI

struct ARGuideSheetView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ARGuideStatusSectionView(viewModel: viewModel)

                    if viewModel.calibration == nil {
                        CalibrationSectionView(viewModel: viewModel)
                    } else if viewModel.hasImportedSteps == false {
                        ARGuidePracticeUnavailableView()
                    } else {
                        PracticeSectionView(viewModel: viewModel)
                    }

                    if let message = viewModel.calibrationStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("AR 引导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("停止") {
                        Task { @MainActor in
                            viewModel.stopARGuide(using: dismissImmersiveSpace)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverEffect()
                }
            }
        }
        .buttonBorderShape(.roundedRectangle)
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    let appModel = AppModel()
    ARGuideSheetView(viewModel: ARGuideViewModel(appModel: appModel))
}
