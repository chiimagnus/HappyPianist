import SwiftUI

struct PracticeSettingsView: View {
    @Binding var virtualPerformerEnabled: Bool
    let backendStatusText: String?
    let lastImprovStatusText: String?
    let recordingSourceText: String?
    let isAIPerformanceActive: Bool
    let isVirtualPianoMode: Bool
    let gazePlaneDiskStatusText: String?
    let onOpenTakeLibrary: () -> Void
    let onRetryVirtualPianoPlacement: () -> Void

    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage("practiceManualAdvanceMode") private var manualAdvanceModeRawValue = ManualAdvanceMode.step.rawValue
    @AppStorage(PracticeSessionViewModel.practiceHandSeparatedStepMatchingEnabledKey)
    private var practiceHandSeparatedStepMatchingEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("AI 即兴演奏（虚拟演奏家）", isOn: $virtualPerformerEnabled)
            if virtualPerformerEnabled {
                if let backendStatusText {
                    Text(backendStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let lastImprovStatusText {
                    Text(lastImprovStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let recordingSourceText {
                Text(recordingSourceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("打开录制库", systemImage: "list.bullet") {
                onOpenTakeLibrary()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()

            Divider()

            Toggle("调试：显示键盘坐标轴（X/Y/Z）", isOn: $debugKeyboardAxesOverlayEnabled)

            Divider()

            Toggle("练习判定：左右手分别满足", isOn: $practiceHandSeparatedStepMatchingEnabled)

            Picker("手动前进方式", selection: $manualAdvanceModeRawValue) {
                ForEach(ManualAdvanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if isVirtualPianoMode {
                Divider()

                if let gazePlaneDiskStatusText {
                    Text(gazePlaneDiskStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("重试放置", systemImage: "arrow.clockwise") {
                    onRetryVirtualPianoPlacement()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
            }
        }
        .padding(16)
        .frame(minWidth: 320)
        .disabled(isAIPerformanceActive)
    }
}

#Preview("练习设置") {
    PracticeSettingsView(
        virtualPerformerEnabled: .constant(false),
        backendStatusText: nil,
        lastImprovStatusText: nil,
        recordingSourceText: "录制来源：Bluetooth MIDI（弹奏琴键即可录制）",
        isAIPerformanceActive: false,
        isVirtualPianoMode: true,
        gazePlaneDiskStatusText: "GazePlaneDisk: OK",
        onOpenTakeLibrary: {},
        onRetryVirtualPianoPlacement: {}
    )
}
