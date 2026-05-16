import SwiftUI

struct RealPianoPreparationView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回钢琴类型选择") {
                    router.exitToTypePicker(reason: "user tapped back from real preparation")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("真实钢琴准备")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button("下一步：去选曲") {
                    router.goToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!router.canProceedToLibrary)
            }

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { router.exitToTypePicker(reason: "user exited from real preparation") }
            )
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 700)
        .onChange(of: viewModel.calibrationPhase) {
            router.flowState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
    }
}
