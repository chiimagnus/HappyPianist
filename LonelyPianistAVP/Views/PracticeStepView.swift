import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false

    var body: some View {
        Form {
            Section("状态") {
                LabeledContent("练习") {
                    Text(viewModel.practiceStatusText)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("进度") {
                    Text(viewModel.practiceProgressText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("控制") {
                Text("定位成功后按键位高亮弹奏；也可以使用下方按钮推进步骤。")
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

            Section("定位") {
                Text(viewModel.practiceLocalizationStatusText ?? "进入后会自动定位钢琴。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.canRetryPracticeLocalization {
                    Button("重试定位") {
                        Task { @MainActor in
                            await viewModel.retryPracticeLocalization(
                                using: openImmersiveSpace,
                                dismissImmersiveSpace: dismissImmersiveSpace
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverEffect()
                }

                if viewModel.shouldSuggestCalibrationStep {
                    Text("若持续失败，请返回主页进入 Step 1 重新校准。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("返回主页") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .hoverEffect()
                }
            }
        }
        .buttonBorderShape(.roundedRectangle)
        .onAppear {
            isStepVisible = true
            guard hasRequestedImmersiveOpen == false else { return }
            hasRequestedImmersiveOpen = true

            Task { @MainActor in
                await viewModel.enterPracticeStep(
                    using: openImmersiveSpace,
                    dismissImmersiveSpace: dismissImmersiveSpace
                )

                if isStepVisible == false {
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
            }
        }
        .onDisappear {
            isStepVisible = false
            hasRequestedImmersiveOpen = false
            viewModel.resetPracticeLocalizationState()
            Task { @MainActor in
                await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                await viewModel.recoverImmersiveStateIfStuck()
            }
        }
    }

    @ViewBuilder
    private var practiceButtons: some View {
        Button("跳过") { viewModel.skipStep() }
            .buttonStyle(.bordered)
            .hoverEffect()
            .disabled(viewModel.canControlPractice == false)

        Button("标记为正确") { viewModel.markCorrect() }
            .buttonStyle(.borderedProminent)
            .hoverEffect()
            .disabled(viewModel.canControlPractice == false)
    }
}

#Preview("Step 2") {
    PracticeStepView(viewModel: ARGuideViewModel(appModel: AppModel()))
}
