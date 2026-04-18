import SwiftUI

struct ARGuideSheetView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionBox("状态", spacing: 8) {
                        SecondaryCaption(viewModel.handTrackingStatusText)
                        SecondaryCaption(viewModel.practiceStatusText)
                    }

                    if viewModel.calibration == nil {
                        SectionBox("校准") {
                            CalibrationInstructions()
                            SecondaryCaption(captureHintText)

                            AdaptiveButtonRow(spacing: 10) {
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

                            Button("手动微调") {
                                viewModel.enterManualAdjustMode()
                            }
                            .buttonStyle(.bordered)
                            .hoverEffect()

                            if viewModel.calibrationCaptureService.mode == .manualFallback {
                                VStack(alignment: .leading, spacing: 8) {
                                    SecondaryCaption("微调（手动模式）")
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
                        SectionBox("练习") {
                            SecondaryCaption("请先在主窗口导入 MusicXML，然后再回来开始练习。")
                        }
                    } else {
                        SectionBox("练习") {
                            SecondaryCaption("按键位高亮弹奏；也可以用下方按钮推进步骤。")
                            AdaptiveButtonRow(spacing: 10) {
                                Button("跳过") { viewModel.skipStep() }
                                    .buttonStyle(.bordered)
                                    .hoverEffect()
                                Button("标记为正确") { viewModel.markCorrect() }
                                    .buttonStyle(.bordered)
                                    .hoverEffect()
                            }
                        }
                    }

                    if let message = viewModel.calibrationStatusMessage {
                        SecondaryCaption(message)
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

    private var captureHintText: String {
        guard let pending = viewModel.pendingCalibrationCaptureAnchor else {
            return "提示：先在空间轻点一次可更新准星位置；选择“设置 A0/C8”后，再轻点一次完成捕获。"
        }
        return "待捕获：\(pending == .a0 ? "A0" : "C8")（现在在空间轻点一次完成捕获）"
    }
}

private struct SectionBox<Content: View>: View {
    let title: String
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(_ title: String, spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.title = title
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SecondaryCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdaptiveButtonRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits {
            AnyLayout(HStackLayout(spacing: spacing)) {
                content
            }
            AnyLayout(VStackLayout(alignment: .leading, spacing: spacing)) {
                content
            }
        }
    }
}

private struct CalibrationInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("步骤：")
                .font(.callout)
                .fontWeight(.semibold)
            SecondaryCaption("（提示：每次进入 AR 引导都会要求重新校准。）")
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
