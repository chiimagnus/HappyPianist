import SwiftUI

struct RealPianoPreparationView: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回钢琴类型选择") {
                    coordinator.resetToPreparation(reason: "user tapped back from real preparation")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("真实钢琴准备")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button("下一步：去选曲") {
                    coordinator.openLibrary(dismissCurrent: .preparation, openWindow: openWindow, dismissWindow: dismissWindow)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedToLibrary)
            }

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { coordinator.resetToPreparation(reason: "user exited from real preparation") }
            )
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 700)
        .onChange(of: viewModel.calibrationPhase) {
            coordinator.flowState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
    }

    private var canProceedToLibrary: Bool {
        coordinator.pianoModeRegistry
            .mode(for: coordinator.flowState.selectedPianoModeID)?
            .canProceedToLibrary(flowState: coordinator.flowState) ?? false
    }
}
