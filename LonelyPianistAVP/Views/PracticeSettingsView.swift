import SwiftUI

struct PracticeSettingsView: View {
    @Binding var virtualPianoEnabled: Bool
    @Binding var virtualPerformerEnabled: Bool
    let backendStatusText: String?
    let lastImprovStatusText: String?

    @AppStorage("practiceAudioRecognitionDebugOverlayEnabled") private var practiceAudioRecognitionDebugOverlayEnabled =
        false
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage("immersivePanoramaEnabled") private var immersivePanoramaEnabled = false
    @AppStorage("practiceManualAdvanceMode") private var manualAdvanceModeRawValue = ManualAdvanceMode.step.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("虚拟钢琴（无需真实钢琴）", isOn: $virtualPianoEnabled)
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
            Toggle("沉浸式：360° 全景背景", isOn: $immersivePanoramaEnabled)

            Divider()

            Toggle("调试：显示音频识别 overlay", isOn: $practiceAudioRecognitionDebugOverlayEnabled)
            Toggle("调试：显示键盘坐标轴（X/Y/Z）", isOn: $debugKeyboardAxesOverlayEnabled)

            Picker("手动前进方式", selection: $manualAdvanceModeRawValue) {
                ForEach(ManualAdvanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}

#Preview("练习设置") {
    PracticeSettingsView(
        virtualPianoEnabled: .constant(false),
        virtualPerformerEnabled: .constant(false),
        backendStatusText: nil,
        lastImprovStatusText: nil
    )
}
