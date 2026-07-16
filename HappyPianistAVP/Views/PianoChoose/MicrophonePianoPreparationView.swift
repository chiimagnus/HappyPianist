import SwiftUI

struct RealPianoPreparationView: View {
    @Environment(WindowTransitionState.self) private var windowState
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

                Button("下一步：去选曲") {
                    navigationActions.nextToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedToLibrary)
            }

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { windowState.resetToPreparation(reason: "user exited from real preparation") }
            )
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 700)
        .onChange(of: viewModel.calibrationPhase) {
            windowState.practiceSetupState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
    }

    private var canProceedToLibrary: Bool {
        windowState.pianoModeRegistry
            .mode(for: windowState.practiceSetupState.selectedPianoModeID)?
            .canProceedToLibrary(context: PianoModeReadinessContext(practiceSetupState: windowState.practiceSetupState)) ?? false
    }
}
