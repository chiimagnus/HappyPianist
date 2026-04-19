import SwiftUI

struct CalibrationStepView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var immersiveLifecycleMessage: String?

    var body: some View {
        Form {
            Section("说明") {
                Text("在沉浸空间中依次捕获 A0 / C8 后保存校准。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("校准") {
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
            }

            if viewModel.storedCalibration != nil {
                Section("当前校准") {
                    Text("当前校准已保存（待定位）。若键位高亮存在偏差，可重新校准。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("重新校准") {
                        viewModel.beginCalibrationRecapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverEffect()
                }
            }

            if let message = viewModel.calibrationStatusMessage {
                Section("状态") {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    mode: .calibration,
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
    private var calibrationButtons: some View {
        Button("设置 A0") { viewModel.pendingCalibrationCaptureAnchor = .a0 }
            .buttonStyle(.bordered)
            .hoverEffect()
        Button("设置 C8") { viewModel.pendingCalibrationCaptureAnchor = .c8 }
            .buttonStyle(.bordered)
            .hoverEffect()
        Button("保存") { viewModel.saveCalibration() }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.calibrationCaptureService.a0AnchorID == nil ||
                viewModel.calibrationCaptureService.c8AnchorID == nil
            )
            .hoverEffect()
    }

    private var captureHintText: String {
        guard let pending = viewModel.pendingCalibrationCaptureAnchor else {
            return "提示：先点“设置 A0 / 设置 C8”。把左手食指按在对应琴键上，等待准星变绿（稳定）后，用右手捏合一次确认。"
        }
        return "待锁定：\(pending == .a0 ? "A0" : "C8")（左手食指放稳，准星变绿后右手捏合确认）"
    }
}

#Preview("Step 1 - 初始") {
    let appModel = AppModel()
    appModel.calibrationStatusMessage = "请重新校准"
    return CalibrationStepView(viewModel: ARGuideViewModel(appModel: appModel))
}

#Preview("Step 1 - 已校准") {
    let appModel = AppModel()
    appModel.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )
    appModel.calibrationStatusMessage = "已保存校准（待定位）"
    return CalibrationStepView(viewModel: ARGuideViewModel(appModel: appModel))
}
