import SwiftUI

struct CalibrationStepView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
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

        return ZStack {
            CalibrationStageCard(
                stage: CalibrationCardStage(phase: phase),
                phase: phase,
                storedCalibration: viewModel.storedCalibration,
                isReticleReadyToConfirm: isReticleReadyToConfirm,
                errorMessage: errorMessage,
                onReturnHome: { dismiss() },
                simulatorDemoState: simulatorDemoState,
                onSimulatorDemoAdvance: simulatorDemoState == nil ? nil : { handleSimulatorDemoAdvance() }
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isStepVisible = true

            if isSimulatorDemoActive {
                viewModel.endCalibrationGuidedFlow()
                #if DEBUG
                viewModel.setCalibrationPhaseForPreview(.capturingA0)
                #endif
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
            isStepVisible = false
            hasRequestedImmersiveOpen = false
            #if DEBUG && targetEnvironment(simulator)
            simulatorDemoTask?.cancel()
            simulatorDemoTask = nil
            #endif
            viewModel.endCalibrationGuidedFlow()

            if isSimulatorDemoActive == false {
                Task { @MainActor in
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
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
                    dismiss()

                case .error:
                    viewModel.setCalibrationPhaseForPreview(.capturingA0)

                default:
                    break
            }
        }
        #endif
    }
}

private enum CalibrationSimulatorDemoState: Hashable {
    case enabled
}

private enum CalibrationCardStage: Hashable {
    case capturingA0
    case capturingC8
    case completed
    case error

    init(phase: ARGuideViewModel.CalibrationPhase) {
        switch phase {
            case .capturingA0, .transitionA0:
                self = .capturingA0
            case .capturingC8, .transitionC8:
                self = .capturingC8
            case .completed:
                self = .completed
            case .error:
                self = .error
        }
    }
}

private struct CalibrationStageCard: View {
    let stage: CalibrationCardStage
    let phase: ARGuideViewModel.CalibrationPhase
    let storedCalibration: StoredWorldAnchorCalibration?
    let isReticleReadyToConfirm: Bool
    let errorMessage: String?
    let onReturnHome: () -> Void
    let simulatorDemoState: CalibrationSimulatorDemoState?
    let onSimulatorDemoAdvance: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if stage == .capturingA0 || stage == .capturingC8 {
                PianoKeyboard88View(
                    highlightedMIDINotes: highlightedMIDINotes,
                    highlightColorByMIDINote: highlightColorByMIDINote
                )
                .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    KeyboardMovingGlowOverlay(
                        isActive: showsMovingGlow,
                        startFraction: PianoKeyboard88View.keyCenterFraction(midiNote: PianoKeyboard88View.minPlayableMIDINote) ?? 0,
                        endFraction: PianoKeyboard88View.keyCenterFraction(midiNote: PianoKeyboard88View.maxPlayableMIDINote) ?? 1
                    )
                }

                Text(step == .a0 ? "左手食指放在 A0 键，准星变绿后捏合确认。" : "左手食指移到 C8 键，准星变绿后捏合确认。")
                    .font(.callout)

                Text(isReticleReadyToConfirm ? "已就绪：现在可捏合确认" : "等待稳定：准星变绿后再捏合确认")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if DEBUG && targetEnvironment(simulator)
                if simulatorDemoState == .enabled, let onSimulatorDemoAdvance {
                    HStack {
                        Text("模拟器演示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("下一步") {
                            onSimulatorDemoAdvance()
                        }
                        .buttonStyle(.borderedProminent)
                        .hoverEffect()
                    }
                }
                #endif
            } else if stage == .completed {
                completionBody
            } else if stage == .error {
                errorBody
            }
        }
        .padding(18)
        .frame(maxWidth: stage == .capturingA0 || stage == .capturingC8 ? 920 : 720)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.12))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: stage)
    }

    private var completionBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("校准完成")
                    .font(.title2.weight(.semibold))

                if let estimatedKeyboardWidthText {
                    Text(estimatedKeyboardWidthText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Button("返回首页") {
                onReturnHome()
            }
            .buttonStyle(.borderedProminent)
            .hoverEffect()
        }
        .frame(maxWidth: .infinity)
    }

    private var errorBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.red)

            VStack(spacing: 6) {
                Text("无法校准")
                    .font(.title2.weight(.semibold))
                Text(errorMessage ?? "手部追踪不可用，无法进入校准流程。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("返回首页") {
                onReturnHome()
            }
            .buttonStyle(.borderedProminent)
            .hoverEffect()
        }
        .frame(maxWidth: .infinity)
    }

    private var step: CalibrationAnchorPoint {
        stage == .capturingC8 ? .c8 : .a0
    }

    private var isA0Locked: Bool {
        phase == .transitionA0 || stage == .capturingC8 || stage == .completed
    }

    private var showsMovingGlow: Bool {
        phase == .transitionA0
    }

    private var highlightedMIDINotes: Set<Int> {
        switch step {
            case .a0:
                [21]
            case .c8:
                isA0Locked ? [21, 108] : [108]
        }
    }

    private var highlightColorByMIDINote: [Int: Color] {
        switch step {
            case .a0:
                return [21: Color.blue]
            case .c8:
                if isA0Locked {
                    return [21: Color.green, 108: Color.blue]
                }
                return [108: Color.blue]
        }
    }

    private var estimatedKeyboardWidthText: String? {
        guard let storedCalibration else { return nil }
        let estimatedMeters = storedCalibration.whiteKeyWidth * 52
        let estimatedCentimeters = Int((estimatedMeters * 100).rounded())
        return "键盘宽度 · ~\(estimatedCentimeters) cm"
    }
}

private struct KeyboardMovingGlowOverlay: View {
    let isActive: Bool
    let startFraction: CGFloat
    let endFraction: CGFloat

    @State private var progress: CGFloat = 0
    private let animationDurationSeconds: Double = 1.25

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let glowWidth = max(60, width * 0.18)
            let clampedStart = max(0, min(1, startFraction))
            let clampedEnd = max(0, min(1, endFraction))

            let startCenterX = clampedStart * width
            let endCenterX = clampedEnd * width
            let centerX = startCenterX + (progress * (endCenterX - startCenterX))
            let x = centerX - (glowWidth / 2)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.blue.opacity(0.32),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: glowWidth, height: height)
                .blur(radius: 10)
                .offset(x: x, y: 0)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
                .task(id: isActive) {
                    if isActive {
                        withTransaction(Transaction(animation: nil)) {
                            progress = 0
                        }
                        withAnimation(.easeInOut(duration: animationDurationSeconds)) {
                            progress = 1
                        }
                    } else {
                        withTransaction(Transaction(animation: nil)) {
                            progress = 0
                        }
                    }
                }
        }
        .clipShape(.rect(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}

#Preview("Step 1 - A0") {
    let appModel = AppModel()
    let viewModel = ARGuideViewModel(appModel: appModel)
    viewModel.setCalibrationPhaseForPreview(.capturingA0)
    return CalibrationStepView(viewModel: viewModel)
}

#Preview("Step 1 - C8") {
    let appModel = AppModel()
    let viewModel = ARGuideViewModel(appModel: appModel)
    viewModel.setCalibrationPhaseForPreview(.capturingC8)
    return CalibrationStepView(viewModel: viewModel)
}

#Preview("Step 1 - 完成") {
    let appModel = AppModel()
    appModel.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )
    let viewModel = ARGuideViewModel(appModel: appModel)
    viewModel.setCalibrationPhaseForPreview(.completed)
    return CalibrationStepView(viewModel: viewModel)
}

#Preview("Step 1 - 错误") {
    let appModel = AppModel()
    let viewModel = ARGuideViewModel(appModel: appModel)
    viewModel.setCalibrationPhaseForPreview(.error(message: "手部追踪不可用：此设备不支持手部追踪。"))
    return CalibrationStepView(viewModel: viewModel)
}
