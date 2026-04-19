import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var immersiveLifecycleMessage: String?

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
                Text("按键位高亮弹奏；也可以使用下方按钮推进步骤。")
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

            if let immersiveLifecycleMessage {
                Section("沉浸空间") {
                    Text(immersiveLifecycleMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonBorderShape(.roundedRectangle)
        .onAppear {
            isStepVisible = true
            guard hasRequestedImmersiveOpen == false else { return }
            hasRequestedImmersiveOpen = true

            Task { @MainActor in
                immersiveLifecycleMessage = await viewModel.openImmersiveForStep(
                    mode: .practice,
                    using: openImmersiveSpace
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
