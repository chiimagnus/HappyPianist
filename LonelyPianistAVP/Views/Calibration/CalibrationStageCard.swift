import SwiftUI

struct CalibrationStageCard: View {
    @ScaledMetric private var statusIconSize: CGFloat = 72

    let stage: CalibrationCardStage
    let phase: ARGuideViewModel.CalibrationPhase
    let storedCalibration: StoredWorldAnchorCalibration?
    let isReticleReadyToConfirm: Bool
    let errorMessage: String?
    let onReturnHome: () -> Void
    let onRecalibrate: () -> Void
    let simulatorDemoState: CalibrationSimulatorDemoState?
    let onSimulatorDemoAdvance: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
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
                        startFraction: PianoKeyboard88View
                            .keyCenterFraction(midiNote: PianoKeyboard88View.minPlayableMIDINote) ?? 0,
                        endFraction: PianoKeyboard88View
                            .keyCenterFraction(midiNote: PianoKeyboard88View.maxPlayableMIDINote) ?? 1
                    )
                }

                Text(
                    step == .a0
                        ? "左手食指放在 A0 键，准星变绿后用右手捏合确认。"
                        : "右手食指放在 C8 键，准星变绿后用左手捏合确认。"
                )
                .font(.callout)

                Text(
                    isReticleReadyToConfirm
                        ? (step == .a0 ? "已就绪：现在可用右手捏合确认" : "已就绪：现在可用左手捏合确认")
                        : "等待稳定：准星变绿后再捏合确认"
                )
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
                            .buttonBorderShape(.roundedRectangle)
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
        .padding()
    }

    private var completionBody: some View {
        VStack {
            Image(systemName: "checkmark.circle")
                .font(.system(size: statusIconSize, weight: .semibold))
                .foregroundStyle(.green)

            Text("校准完成")
                .font(.title2.weight(.semibold))

            Button("重新校准") {
                onRecalibrate()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle)
        }
        .frame(maxWidth: .infinity)
    }

    private var errorBody: some View {
        VStack {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: statusIconSize, weight: .semibold))
                .foregroundStyle(.red)

            VStack {
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
            .buttonBorderShape(.roundedRectangle)
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
}
