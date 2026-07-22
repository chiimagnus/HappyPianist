import SwiftUI

struct RealPianoPreparationView: View {
    @Environment(PianoSetupCoordinator.self) private var pianoSetupCoordinator
    @Environment(\.preparationNavigationActions) private var navigationActions
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回钢琴类型选择") {
                    navigationActions.backToTypePicker()
                }

                Spacer()

                Text("真实钢琴准备")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button("完成设置") {
                    navigationActions.finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!pianoSetupCoordinator.isSetupReady)
            }

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { pianoSetupCoordinator.reset() }
            )
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 700)
        .onChange(of: viewModel.calibrationPhase) {
            pianoSetupCoordinator.practiceSetupState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
    }
}
