import SwiftUI

struct ARGuideSheetView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    LabeledContent("手部追踪") {
                        Text(viewModel.handTrackingStatusText)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("练习") {
                        Text(viewModel.practiceStatusText)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.calibration == nil {
                    Section("校准") {
                        CalibrationInstructions()

                        Text(captureHintText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ViewThatFits {
                            AnyLayout(HStackLayout(spacing: 10)) {
                                calibrationButtons
                            }
                            AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) {
                                calibrationButtons
                            }
                        }

                        Button("手动微调") {
                            viewModel.enterManualAdjustMode()
                        }
                        .buttonStyle(.bordered)
                        .hoverEffect()

                        if viewModel.calibrationCaptureService.mode == .manualFallback {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("微调（手动模式）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button("A0 左移") { viewModel.adjust(anchor: .a0, x: -0.01) }
                                        .buttonStyle(.bordered)
                                        .hoverEffect()
                                    Button("A0 右移") { viewModel.adjust(anchor: .a0, x: 0.01) }
                                        .buttonStyle(.bordered)
                                        .hoverEffect()
                                    Button("C8 左移") { viewModel.adjust(anchor: .c8, x: -0.01) }
                                        .buttonStyle(.bordered)
                                        .hoverEffect()
                                    Button("C8 右移") { viewModel.adjust(anchor: .c8, x: 0.01) }
                                        .buttonStyle(.bordered)
                                        .hoverEffect()
                                }
                            }
                        }
                    }
                } else if viewModel.hasImportedSteps == false {
                    Section("练习") {
                        Text("请先在主窗口导入 MusicXML，然后再回来开始练习。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("练习") {
                        Text("按键位高亮弹奏；也可以用下方按钮推进步骤。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ViewThatFits {
                            AnyLayout(HStackLayout(spacing: 10)) {
                                practiceButtons
                            }
                            AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) {
                                practiceButtons
                            }
                        }
                    }
                }

                if let message = viewModel.calibrationStatusMessage {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

    @ViewBuilder
    private var calibrationButtons: some View {
        Button("设置 A0") { viewModel.pendingCalibrationCaptureAnchor = .a0 }
            .buttonStyle(.bordered)
            .hoverEffect()
        Button("设置 C8") { viewModel.pendingCalibrationCaptureAnchor = .c8 }
            .buttonStyle(.bordered)
            .hoverEffect()
        Button("保存") { viewModel.saveCalibration() }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.calibrationCaptureService.buildCalibration() == nil)
            .hoverEffect()
    }

    @ViewBuilder
    private var practiceButtons: some View {
        Button("跳过") { viewModel.skipStep() }
            .buttonStyle(.bordered)
            .hoverEffect()
        Button("标记为正确") { viewModel.markCorrect() }
            .buttonStyle(.bordered)
            .hoverEffect()
    }

    private var captureHintText: String {
        guard let pending = viewModel.pendingCalibrationCaptureAnchor else {
            return "提示：先在空间轻点一次可更新准星位置；选择“设置 A0/C8”后，再轻点一次完成捕获。"
        }
        return "待捕获：\(pending == .a0 ? "A0" : "C8")（现在在空间轻点一次完成捕获）"
    }
}

private struct CalibrationInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("步骤：")
                .font(.callout)
                .fontWeight(.semibold)
            Text("（提示：每次进入 AR 引导都会要求重新校准。）")
                .foregroundStyle(.secondary)
            Text("1) 点“设置 A0”，然后在空间轻点一次，把点放到 A0 键中心上方。")
            Text("2) 点“设置 C8”，同样捕获 C8 键中心上方。")
            Text("3) 点“保存”。重启后仍能加载即为通过。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    let appModel = AppModel()
    ARGuideSheetView(viewModel: ARGuideViewModel(appModel: appModel))
}
