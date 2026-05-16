import SwiftUI

struct CalibrationStepView: View {
    @Bindable var viewModel: ARGuideViewModel
    let onExit: () -> Void
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false

    #if DEBUG && targetEnvironment(simulator)
        @State private var simulatorDemoEnabled = true
        @State private var simulatorDemoTask: Task<Void, Never>?
    #endif

    var body: some View {
        let phase = viewModel.calibrationPhase
        let errorMessage: String? = {
            if case let .error(message) = phase {
                return message
            }
            return nil
        }()

        return CalibrationStageCard(
            stage: CalibrationCardStage(phase: phase),
            phase: phase,
            storedCalibration: viewModel.storedCalibration,
            isReticleReadyToConfirm: isReticleReadyToConfirm,
            errorMessage: errorMessage,
            onReturnHome: { onExit() },
            onRecalibrate: { beginRecalibration() },
            simulatorDemoState: simulatorDemoState,
            onSimulatorDemoAdvance: simulatorDemoState == nil ? nil : { handleSimulatorDemoAdvance() }
        )
        .onAppear {
            isStepVisible = true

            if isSimulatorDemoActive {
                viewModel.endCalibrationGuidedFlow()
                #if DEBUG
                    viewModel.setCalibrationPhaseForPreview(.capturingA0)
                #endif
                return
            }

            if viewModel.showCalibrationCompletedIfStoredCalibrationExists() {
                return
            }

            viewModel.beginCalibrationGuidedFlow()
            guard hasRequestedImmersiveOpen == false else { return }
            hasRequestedImmersiveOpen = true

            Task { @MainActor in
                let openError = await viewModel.openImmersiveForStep(
                    mode: .calibration,
                    using: openImmersiveSpace
                )
                if let openError {
                    viewModel.presentCalibrationError(message: openError)
                }

                if isStepVisible == false {
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
            }
        }
        .onDisappear {
            let shouldCloseImmersive = hasRequestedImmersiveOpen
            isStepVisible = false
            hasRequestedImmersiveOpen = false
            #if DEBUG && targetEnvironment(simulator)
                simulatorDemoTask?.cancel()
                simulatorDemoTask = nil
            #endif
            viewModel.endCalibrationGuidedFlow()

            if isSimulatorDemoActive == false, shouldCloseImmersive {
                Task { @MainActor in
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
            }
        }
    }

    private func beginRecalibration() {
        viewModel.beginCalibrationGuidedFlow()
        guard hasRequestedImmersiveOpen == false else { return }
        hasRequestedImmersiveOpen = true

        Task { @MainActor in
            let openError = await viewModel.openImmersiveForStep(
                mode: .calibration,
                using: openImmersiveSpace
            )
            if let openError {
                viewModel.presentCalibrationError(message: openError)
            }

            if isStepVisible == false {
                await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                await viewModel.recoverImmersiveStateIfStuck()
            }
        }
    }

    private var isReticleReadyToConfirm: Bool {
        #if DEBUG && targetEnvironment(simulator)
            if isSimulatorDemoActive { return true }
        #endif
        return viewModel.calibrationCaptureService.isReticleReadyToConfirm
    }

    private var isSimulatorDemoActive: Bool {
        #if DEBUG && targetEnvironment(simulator)
            return simulatorDemoEnabled
        #else
            return false
        #endif
    }

    private var simulatorDemoState: CalibrationSimulatorDemoState? {
        #if DEBUG && targetEnvironment(simulator)
            return isSimulatorDemoActive ? .enabled : nil
        #else
            return nil
        #endif
    }

    private func handleSimulatorDemoAdvance() {
        #if DEBUG && targetEnvironment(simulator)
            guard isSimulatorDemoActive else { return }

            simulatorDemoTask?.cancel()
            simulatorDemoTask = Task { @MainActor in
                switch viewModel.calibrationPhase {
                    case .capturingA0:
                        viewModel.setCalibrationPhaseForPreview(.transitionA0)
                        try? await Task.sleep(for: .seconds(1.25))
                        guard Task.isCancelled == false else { return }
                        viewModel.setCalibrationPhaseForPreview(.capturingC8)

                    case .capturingC8:
                        viewModel.setCalibrationPhaseForPreview(.transitionC8)
                        try? await Task.sleep(for: .seconds(0.3))
                        guard Task.isCancelled == false else { return }
                        viewModel.setCalibrationPhaseForPreview(.completed)

                    case .completed:
                        onExit()

                    case .error:
                        viewModel.setCalibrationPhaseForPreview(.capturingA0)

                    default:
                        break
                }
            }
        #endif
    }
}
