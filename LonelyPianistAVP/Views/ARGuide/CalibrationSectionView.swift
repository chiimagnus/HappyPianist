import SwiftUI

struct CalibrationSectionView: View {
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        GroupBox("校准") {
            VStack(alignment: .leading, spacing: 12) {
                CalibrationInstructionsView()

                Text(captureHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ControlGroup {
                    Button("设置 A0") { viewModel.pendingCalibrationCaptureAnchor = .a0 }
                        .hoverEffect()
                    Button("设置 C8") { viewModel.pendingCalibrationCaptureAnchor = .c8 }
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
                    ManualAdjustRowView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var captureHintText: String {
        guard let pending = viewModel.pendingCalibrationCaptureAnchor else {
            return "提示：先在空间轻点一次可更新准星位置；选择“设置 A0/C8”后，再轻点一次完成捕获。"
        }
        return "待捕获：\(pending == .a0 ? "A0" : "C8")（现在在空间轻点一次完成捕获）"
    }
}

private struct CalibrationInstructionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("步骤：")
                .font(.callout)
                .fontWeight(.semibold)
            Text("（提示：每次进入 AR 引导都会要求重新校准。）")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("1) 点“设置 A0”，然后在空间轻点一次，把点放到 A0 键中心上方。")
            Text("2) 点“设置 C8”，同样捕获 C8 键中心上方。")
            Text("3) 点“保存”。重启后仍能加载即为通过。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ManualAdjustRowView: View {
    let viewModel: ARGuideViewModel

    var body: some View {
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

#Preview {
    let appModel = AppModel()
    CalibrationSectionView(viewModel: ARGuideViewModel(appModel: appModel))
        .padding()
}
